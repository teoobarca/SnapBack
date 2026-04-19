package com.snapback.mobile.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.snapback.mobile.R
import com.snapback.mobile.net.MdnsAdvertiser
import com.snapback.mobile.net.MessageServer
import com.snapback.mobile.net.WifiLocks
import com.snapback.mobile.protocol.ProtocolMessage
import com.snapback.mobile.security.KeystoreTokenStore

class MobileForegroundService : Service() {
    private var server: MessageServer? = null
    private var mdns: MdnsAdvertiser? = null
    private var locks: WifiLocks? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Waiting for Mac"))
        startBridge()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        stopBridge()
        super.onDestroy()
    }

    private fun startBridge() {
        val token = KeystoreTokenStore(this).read() ?: run {
            Log.w(TAG, "no paired token; foreground service running but idle")
            return
        }
        val locks = WifiLocks(this).also { it.holdMulticast() }
        this.locks = locks

        val server = MessageServer(token, DEFAULT_PORT) { msg: ProtocolMessage ->
            onMessage(msg)
        }
        server.start()
        this.server = server

        val mdns = MdnsAdvertiser(this).also { it.start(DEFAULT_PORT) }
        this.mdns = mdns
    }

    private fun stopBridge() {
        server?.stop(); server = null
        mdns?.stop(); mdns = null
        locks?.releaseMulticast(); locks?.releaseHighPerfWifi()
        locks = null
    }

    private fun onMessage(msg: ProtocolMessage) {
        // Slice A: observe only. Lock wiring arrives in Phase 5.
        Log.i(TAG, "received ${msg.type.wire}")
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

    companion object {
        private const val TAG = "SnapBack/fgs"
        private const val CHANNEL_ID = "snapback-bridge"
        private const val NOTIF_ID = 1001
        const val DEFAULT_PORT = 45782

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
    }
}
