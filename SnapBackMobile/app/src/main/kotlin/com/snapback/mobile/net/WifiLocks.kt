package com.snapback.mobile.net

import android.content.Context
import android.net.wifi.WifiManager

/**
 * Bundled wifi locks:
 *   • MulticastLock stays held for the service lifetime (mDNS works with screen off).
 *   • WifiLock(HIGH_PERF) held ONLY while HOLD is outstanding (§5.8).
 */
class WifiLocks(context: Context) {
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val multicast = wifi.createMulticastLock("snapback-mdns").apply { setReferenceCounted(false) }
    private val wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "snapback-hold")
        .apply { setReferenceCounted(false) }

    fun holdMulticast() { if (!multicast.isHeld) multicast.acquire() }
    fun releaseMulticast() { if (multicast.isHeld) multicast.release() }

    fun holdHighPerfWifi() { if (!wifiLock.isHeld) wifiLock.acquire() }
    fun releaseHighPerfWifi() { if (wifiLock.isHeld) wifiLock.release() }
}
