package com.snapback.mobile.lock

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context

class SnapBackDeviceAdminReceiver : DeviceAdminReceiver() {
    companion object {
        fun lockViaDeviceAdmin(context: Context): Boolean {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val admin = ComponentName(context, SnapBackDeviceAdminReceiver::class.java)
            if (!dpm.isAdminActive(admin)) return false
            return try { dpm.lockNow(); true } catch (e: SecurityException) { false }
        }
    }
}
