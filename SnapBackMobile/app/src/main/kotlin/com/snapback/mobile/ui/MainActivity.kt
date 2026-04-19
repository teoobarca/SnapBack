package com.snapback.mobile.ui

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.snapback.mobile.lock.LockDriver
import com.snapback.mobile.pair.PairingActivity
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.service.MobileForegroundService

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val paired = remember { KeystoreTokenStore(this).read() != null }
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("SnapBack Mobile", style = MaterialTheme.typography.headlineMedium)
                    Spacer(Modifier.height(24.dp))
                    if (paired) {
                        Text("Bridge connected.", style = MaterialTheme.typography.bodyLarge)
                        Spacer(Modifier.height(8.dp))
                        Text("1.4.0 slice B — tap below to confirm lock works.",
                             style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(24.dp))
                        Button(onClick = {
                            val tier = LockDriver(this@MainActivity).lock()
                            android.widget.Toast.makeText(
                                this@MainActivity,
                                "Lock attempted: $tier", android.widget.Toast.LENGTH_SHORT
                            ).show()
                        }) { Text("Test lock") }
                        Spacer(Modifier.height(12.dp))
                        Button(onClick = {
                            KeystoreTokenStore(this@MainActivity).delete()
                            MobileForegroundService.stop(this@MainActivity)
                            recreate()
                        }) { Text("Unpair") }
                    } else {
                        Text("Not paired.", style = MaterialTheme.typography.bodyLarge)
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = {
                            startActivity(Intent(this@MainActivity, PairingActivity::class.java))
                        }) { Text("Pair with Mac") }
                    }
                }
            }
        }
    }
}
