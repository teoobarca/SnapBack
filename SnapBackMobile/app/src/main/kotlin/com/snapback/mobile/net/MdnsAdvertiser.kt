package com.snapback.mobile.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log

class MdnsAdvertiser(private val context: Context) {
    private var nsd: NsdManager? = null
    private var listener: NsdManager.RegistrationListener? = null
    private var registered = false

    fun start(port: Int) {
        if (registered) return
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        this.nsd = nsd

        val info = NsdServiceInfo().apply {
            serviceName = "snapback-" + Build.MODEL.filter { it.isLetterOrDigit() }
                .take(16).ifEmpty { "device" }
            serviceType = "_snapback._tcp"
            this.port = port
            setAttribute("device_name", Build.MODEL)
        }
        val l = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(s: NsdServiceInfo) {
                Log.i(TAG, "mdns registered: ${s.serviceName}@${s.port}")
                registered = true
            }
            override fun onRegistrationFailed(s: NsdServiceInfo, code: Int) {
                Log.w(TAG, "mdns register failed: $code")
            }
            override fun onServiceUnregistered(s: NsdServiceInfo) {
                Log.i(TAG, "mdns unregistered")
                registered = false
            }
            override fun onUnregistrationFailed(s: NsdServiceInfo, code: Int) {
                Log.w(TAG, "mdns unregister failed: $code")
            }
        }
        listener = l
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, l)
    }

    fun stop() {
        val nsd = this.nsd ?: return
        val l = this.listener ?: return
        try { nsd.unregisterService(l) } catch (e: Exception) {}
        listener = null
    }

    companion object { private const val TAG = "SnapBack/mdns" }
}
