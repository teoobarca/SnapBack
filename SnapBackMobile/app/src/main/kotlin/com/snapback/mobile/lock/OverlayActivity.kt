package com.snapback.mobile.lock

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.snapback.mobile.ui.theme.SnapBackColors

class OverlayActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Box(modifier = Modifier.fillMaxSize().background(SnapBackColors.OverlayBg)) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Box(
                        modifier = Modifier
                            .width(48.dp)
                            .height(4.dp)
                            .background(SnapBackColors.Orange, RoundedCornerShape(2.dp))
                    )
                    Spacer(Modifier.height(32.dp))
                    Icon(
                        Icons.Rounded.Lock,
                        contentDescription = null,
                        tint = SnapBackColors.Orange,
                        modifier = Modifier.size(64.dp),
                    )
                    Spacer(Modifier.height(24.dp))
                    Text(
                        "Claude is waiting on your Mac.",
                        color = Color.White,
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "This overlay will dismiss once you respond.",
                        color = SnapBackColors.MutedGray,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                    )
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
