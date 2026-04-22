package com.snapback.mobile.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.snapback.mobile.BuildConfig
import com.snapback.mobile.R
import com.snapback.mobile.lock.LockDriver
import com.snapback.mobile.lock.OverlayActivity
import com.snapback.mobile.net.MdnsAdvertiser
import com.snapback.mobile.net.MessageServer
import com.snapback.mobile.net.WifiLocks
import com.snapback.mobile.db.AppDatabase
import com.snapback.mobile.db.EventRow
import com.snapback.mobile.protocol.JsonValue
import com.snapback.mobile.protocol.ProtocolMessage
import com.snapback.mobile.protocol.ProtocolMessageType
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.state.HoldStateMachine
import com.snapback.mobile.state.ScreenStateGate
import com.snapback.mobile.state.TransitionEffect
import kotlinx.coroutines.*

class MobileForegroundService : Service() {
    private var server: MessageServer? = null
    private var mdns: MdnsAdvertiser? = null
    private var locks: WifiLocks? = null
    private var lockDriver: LockDriver? = null
    private var sm: HoldStateMachine? = null
    private var userPresentReceiver: UserPresentReceiver? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var ttlJob: Job? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activeSecret: ByteArray? = null
    private var _clientConnected = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        ensureNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Bridge idle"))
        startBridge()
        registerUserPresent()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val stored = KeystoreTokenStore(this).read()
        if (stored != null && !stored.contentEquals(activeSecret)) {
            Log.i(TAG, "token changed (re-pair); restarting bridge")
            stopBridge()
            // Delay to let the old ServerSocket fully release port 45782.
            scope.launch {
                delay(500)
                mainHandler.post { startBridge() }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterUserPresent()
        stopBridge()
        scope.cancel()
        instance = null
        super.onDestroy()
    }

    private fun startBridge() {
        val token = KeystoreTokenStore(this).read() ?: run {
            Log.w(TAG, "no paired token; service idle")
            activeSecret = null
            return
        }
        activeSecret = token
        val locks = WifiLocks(this).also { it.holdMulticast() }
        this.locks = locks
        this.lockDriver = LockDriver(this)
        this.sm = HoldStateMachine(ttlMs = BuildConfig.HOLD_TTL_MS)

        val sm = this.sm!!
        val server = MessageServer(token, DEFAULT_PORT, { msg -> mainHandler.post { onMessage(msg) } },
            holdStateProvider = { sm.state == com.snapback.mobile.state.HoldState.Hold })
        server.onClientConnected = {
            mainHandler.post {
                _clientConnected = true
                updateNotification("Connected to Mac")
            }
        }
        server.onClientDisconnected = {
            mainHandler.post {
                _clientConnected = false
                updateNotification("Bridge idle")
            }
        }
        server.start()
        this.server = server

        val mdns = MdnsAdvertiser(this).also { it.start(DEFAULT_PORT) }
        this.mdns = mdns
    }

    private fun stopBridge() {
        ttlJob?.cancel(); ttlJob = null
        server?.stop(); server = null
        mdns?.stop(); mdns = null
        locks?.releaseMulticast(); locks?.releaseHighPerfWifi()
        locks = null
        _clientConnected = false
    }

    private fun registerUserPresent() {
        val r = UserPresentReceiver()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(r, IntentFilter(Intent.ACTION_USER_PRESENT), Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(r, IntentFilter(Intent.ACTION_USER_PRESENT))
        }
        userPresentReceiver = r
    }

    private fun unregisterUserPresent() {
        val r = userPresentReceiver ?: return
        try { unregisterReceiver(r) } catch (_: Exception) {}
        userPresentReceiver = null
    }

    private fun logEvent(now: Long, kind: String, detail: String) {
        scope.launch {
            val db = AppDatabase.get(this@MobileForegroundService)
            db.events().insert(EventRow(timestamp = now, kind = kind, detail = detail))
            db.events().trim()
        }
    }

    private fun onMessage(msg: ProtocolMessage) {
        val sm = this.sm ?: return
        val now = System.currentTimeMillis()
        when (msg.type) {
            ProtocolMessageType.Attention -> {
                val hook = (msg.payload.firstOrNull { it.first == "hook" }?.second as? JsonValue.Str)?.value ?: "Stop"
                logEvent(now, msg.type.wire, hook)
                val passes = ScreenStateGate.passes(this)
                val effect = sm.onAttention(passes, hook, now)
                applyEffect(effect, now)
            }
            ProtocolMessageType.Resume -> {
                logEvent(now, msg.type.wire, "")
                applyEffect(sm.onResume(now), now)
            }
            ProtocolMessageType.Invalidate -> {
                Log.i(TAG, "received invalidate; wiping token and stopping bridge")
                logEvent(now, msg.type.wire, "")
                applyEffect(sm.onResume(now), now)
                KeystoreTokenStore(this).delete()
                activeSecret = null
                stopBridge()
                updateNotification("Unpaired")
            }
            else -> {} // ack/pong/heartbeat/resync handled by server
        }
    }

    private fun applyEffect(effect: TransitionEffect, nowMs: Long) {
        when (effect) {
            TransitionEffect.Ignore -> {}
            TransitionEffect.LockAndArmTimer -> {
                lockDriver?.lock()
                armTtlTimer(nowMs)
                updateNotification("Holding — waiting for Claude resume")
            }
            TransitionEffect.UnlockAndCancelTimer -> {
                OverlayActivity.dismiss()
                ttlJob?.cancel()
                ttlJob = null
                updateNotification("Bridge idle")
            }
            TransitionEffect.RelockAfterGrace -> {
                scope.launch {
                    delay(RELOCK_GRACE_MS)
                    lockDriver?.lock()
                }
            }
        }
    }

    private fun armTtlTimer(startedAt: Long) {
        ttlJob?.cancel()
        ttlJob = scope.launch {
            delay(BuildConfig.HOLD_TTL_MS + 500L)
            val sm = this@MobileForegroundService.sm ?: return@launch
            val now = System.currentTimeMillis()
            applyEffect(sm.onTtlTick(now), now)
        }
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(text))
    }

    private fun ensureNotificationChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, "SnapBack bridge",
                    NotificationManager.IMPORTANCE_LOW
                ).apply { description = "Persistent connection to your paired Mac." }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle("SnapBack Mobile")
            .setContentText(text)
            .setOngoing(true)
            .build()
    }

    fun manualRelease() {
        val sm = this.sm ?: return
        applyEffect(sm.onManualRelease(), System.currentTimeMillis())
    }

    companion object {
        private const val TAG = "SnapBack/fgs"
        private const val CHANNEL_ID = "snapback-bridge"
        private const val NOTIF_ID = 1001
        const val DEFAULT_PORT = 45782
        private const val RELOCK_GRACE_MS = 250L

        @Volatile private var instance: MobileForegroundService? = null

        fun start(context: Context) {
            val intent = Intent(context, MobileForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MobileForegroundService::class.java))
        }

        fun onUserPresent(context: Context) {
            val svc = instance ?: return
            val sm = svc.sm ?: return
            svc.applyEffect(sm.onUserPresent(), System.currentTimeMillis())
        }

        fun manualRelease(context: Context) {
            instance?.manualRelease()
        }

        fun isClientConnected(): Boolean {
            return instance?._clientConnected ?: false
        }
    }
}
