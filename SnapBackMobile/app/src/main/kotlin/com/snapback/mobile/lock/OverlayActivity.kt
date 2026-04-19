package com.snapback.mobile.lock

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Last-resort lock: a fullscreen activity. Dismissible only via the
 * orchestrator's `releaseHold()` finishing it.
 */
class OverlayActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("Claude is waiting on your Mac.", color = Color.White,
                         style = MaterialTheme.typography.headlineMedium)
                    Spacer(Modifier.height(24.dp))
                    Text("This overlay will dismiss once you respond.", color = Color.White,
                         style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        activeInstance = this
    }

    @Deprecated("Swallow back-press by design")
    @Suppress("DEPRECATION")
    override fun onBackPressed() { /* swallow */ }

    override fun onDestroy() {
        if (activeInstance === this) activeInstance = null
        super.onDestroy()
    }

    companion object {
        @Volatile private var activeInstance: OverlayActivity? = null

        fun show(context: Context): Boolean {
            return try {
                val i = Intent(context, OverlayActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                context.startActivity(i)
                true
            } catch (e: Exception) { false }
        }

        fun dismiss() { activeInstance?.finish() }
    }
}
