package com.snapback.mobile.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

class MobileForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        fun start(context: Context) {
            context.startService(Intent(context, MobileForegroundService::class.java))
        }
    }
}
