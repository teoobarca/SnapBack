package com.snapback.mobile.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class UserPresentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_USER_PRESENT) return
        MobileForegroundService.onUserPresent(context)
    }
}
