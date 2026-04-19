package com.snapback.mobile.lock

import android.content.Context
import android.util.Log

enum class LockTier { Accessibility, DeviceAdmin, Overlay, None }

class LockDriver(private val context: Context) {
    fun lock(): LockTier {
        if (SnapBackAccessibilityService.lockViaAccessibility()) {
            Log.i(TAG, "locked via Accessibility")
            return LockTier.Accessibility
        }
        if (SnapBackDeviceAdminReceiver.lockViaDeviceAdmin(context)) {
            Log.i(TAG, "locked via Device Admin")
            return LockTier.DeviceAdmin
        }
        if (OverlayActivity.show(context)) {
            Log.i(TAG, "locked via overlay (weakest)")
            return LockTier.Overlay
        }
        Log.w(TAG, "all lock tiers failed")
        return LockTier.None
    }

    companion object { private const val TAG = "SnapBack/lock" }
}
