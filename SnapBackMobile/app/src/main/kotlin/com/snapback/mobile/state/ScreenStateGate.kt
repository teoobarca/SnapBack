package com.snapback.mobile.state

import android.app.KeyguardManager
import android.content.Context
import android.os.PowerManager

object ScreenStateGate {
    fun passes(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return passes(pm.isInteractive, km.isDeviceLocked)
    }

    fun passes(isInteractive: Boolean, isLocked: Boolean): Boolean {
        return isInteractive && !isLocked
    }
}
