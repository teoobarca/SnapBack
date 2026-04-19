package com.snapback.mobile.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.service.MobileForegroundService
import com.snapback.mobile.ui.theme.SnapBackColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onOpenPair: () -> Unit,
    onUnpair: () -> Unit
) {
    val context = LocalContext.current
    val paired = remember { mutableStateOf(KeystoreTokenStore(context).read() != null) }
    val oem = remember { Oem.current() }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = WindowInsets.statusBars.asPaddingValues().let { statusBar ->
            PaddingValues(
                top = statusBar.calculateTopPadding() + 16.dp,
                bottom = 24.dp,
            )
        },
    ) {
            // --- Connection Status ---
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        if (paired.value) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(10.dp)
                                        .clip(CircleShape)
                                        .background(SnapBackColors.StatusGreen)
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    "Connected",
                                    color = SnapBackColors.StatusGreen,
                                    style = MaterialTheme.typography.titleMedium,
                                )
                            }
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Paired & bridge running.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodyMedium,
                            )

                            Spacer(Modifier.height(16.dp))

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                OutlinedButton(
                                    onClick = { MobileForegroundService.manualRelease(context) },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Icon(Icons.Rounded.LinkOff, contentDescription = null, modifier = Modifier.size(18.dp))
                                    Spacer(Modifier.width(6.dp))
                                    Text("Release Hold")
                                }
                                OutlinedButton(
                                    onClick = {
                                        KeystoreTokenStore(context).delete()
                                        MobileForegroundService.stop(context)
                                        paired.value = false
                                        onUnpair()
                                    },
                                    modifier = Modifier.weight(1f),
                                    colors = ButtonDefaults.outlinedButtonColors(
                                        contentColor = MaterialTheme.colorScheme.error,
                                    ),
                                ) {
                                    Text("Unpair")
                                }
                            }
                        } else {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Icon(
                                    Icons.Rounded.PhoneAndroid,
                                    contentDescription = null,
                                    tint = SnapBackColors.Orange,
                                    modifier = Modifier.size(48.dp),
                                )
                                Spacer(Modifier.height(12.dp))
                                Text(
                                    "Not paired",
                                    style = MaterialTheme.typography.titleMedium,
                                )
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    "Scan the QR code on your Mac to get started.",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Spacer(Modifier.height(16.dp))
                                Button(
                                    onClick = onOpenPair,
                                    modifier = Modifier.fillMaxWidth().height(48.dp),
                                ) {
                                    Text("Pair with Mac")
                                }
                            }
                        }
                    }
                }
            }

            // --- Setup / Permissions ---
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = SnapBackColors.OrangeLight),
                    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Rounded.Info,
                                contentDescription = null,
                                tint = SnapBackColors.Orange,
                                modifier = Modifier.size(20.dp),
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("Setup", style = MaterialTheme.typography.titleMedium)
                        }

                        Spacer(Modifier.height(8.dp))

                        Text(
                            "For SnapBack to lock your phone, it needs Accessibility and Device Admin permissions. Grant both below.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium,
                        )

                        Spacer(Modifier.height(12.dp))

                        OutlinedButton(
                            onClick = { context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.Rounded.Accessibility, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Open Accessibility Settings")
                        }

                        Spacer(Modifier.height(8.dp))

                        OutlinedButton(
                            onClick = { context.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.Rounded.AdminPanelSettings, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Open Device Admin Settings")
                        }
                    }
                }
            }

            // --- Battery ---
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Rounded.BatteryFull,
                                contentDescription = null,
                                tint = SnapBackColors.Orange,
                                modifier = Modifier.size(20.dp),
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("Battery (${oem.displayName})", style = MaterialTheme.typography.titleMedium)
                        }

                        Spacer(Modifier.height(8.dp))

                        Text(
                            OemInstructions.textFor(oem),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )

                        OemInstructions.deepLinkIntent(context, oem)?.let { intent ->
                            Spacer(Modifier.height(12.dp))
                            OutlinedButton(
                                onClick = { context.startActivity(intent) },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text("Open Battery Settings")
                            }
                        }
                    }
                }
            }
    }
}
