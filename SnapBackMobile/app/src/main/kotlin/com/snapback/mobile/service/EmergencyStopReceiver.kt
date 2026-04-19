package com.snapback.mobile.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.snapback.mobile.BuildConfig
import com.snapback.mobile.lock.OverlayActivity

/**
 * Debug-only safety hatch. Disabled via BuildConfig in release.
 *
 *   adb shell am broadcast -a com.snapback.mobile.EMERGENCY_STOP
 */
class EmergencyStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!BuildConfig.EMERGENCY_STOP_ENABLED) return
        if (intent?.action != ACTION) return
        Log.w(TAG, "emergency stop invoked")
        OverlayActivity.dismiss()
        MobileForegroundService.stop(context)
    }

    companion object {
        const val ACTION = "com.snapback.mobile.EMERGENCY_STOP"
        private const val TAG = "SnapBack/emergency"
    }
}
