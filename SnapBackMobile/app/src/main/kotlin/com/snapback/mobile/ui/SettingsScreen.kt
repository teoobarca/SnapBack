package com.snapback.mobile.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.snapback.mobile.db.AppDatabase
import com.snapback.mobile.db.EventRow
import com.snapback.mobile.lock.LockDriver
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.service.MobileForegroundService
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    onOpenPair: () -> Unit,
    onUnpair: () -> Unit
) {
    val context = LocalContext.current
    val paired = remember {
        mutableStateOf(KeystoreTokenStore(context).read() != null)
    }
    val scope = rememberCoroutineScope()
    val events = remember { mutableStateOf(emptyList<EventRow>()) }
    val oem = remember { Oem.current() }

    LaunchedEffect(Unit) {
        if (paired.value) {
            events.value = AppDatabase.get(context).events().recent(50)
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Text("SnapBack Mobile", style = MaterialTheme.typography.headlineMedium) }

        item {
            if (paired.value) {
                Text("Paired & bridge running.", style = MaterialTheme.typography.bodyMedium)
                Row {
                    Button(onClick = {
                        LockDriver(context).lock()
                    }) { Text("Test lock") }
                    Spacer(Modifier.width(12.dp))
                    OutlinedButton(onClick = {
                        MobileForegroundService.manualRelease(context)
                    }) { Text("Release hold") }
                }
                Spacer(Modifier.height(8.dp))
                Button(onClick = {
                    KeystoreTokenStore(context).delete()
                    MobileForegroundService.stop(context)
                    paired.value = false
                    onUnpair()
                }) { Text("Unpair") }
            } else {
                Button(onClick = onOpenPair) { Text("Pair with Mac") }
            }
        }

        item {
            HorizontalDivider()
            Text("Permissions", style = MaterialTheme.typography.titleMedium)
            Button(onClick = {
                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }) { Text("Open Accessibility settings") }
            OutlinedButton(onClick = {
                context.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            }) { Text("Open Device Admin settings") }
        }

        item {
            HorizontalDivider()
            Text("Battery (${oem.displayName})", style = MaterialTheme.typography.titleMedium)
            Text(OemInstructions.textFor(oem), style = MaterialTheme.typography.bodySmall)
            OemInstructions.deepLinkIntent(context, oem)?.let { intent ->
                OutlinedButton(onClick = { context.startActivity(intent) }) {
                    Text("Open battery settings")
                }
            }
        }

        item {
            HorizontalDivider()
            Text("Recent events", style = MaterialTheme.typography.titleMedium)
        }
        items(events.value) { row ->
            Text("${row.timestamp}  ${row.kind}  ${row.detail}",
                 style = MaterialTheme.typography.bodySmall)
        }

        item {
            HorizontalDivider()
            Button(onClick = {
                scope.launch {
                    if (paired.value) {
                        events.value = AppDatabase.get(context).events().recent(50)
                    }
                }
            }) { Text("Refresh events") }
        }
    }
}
