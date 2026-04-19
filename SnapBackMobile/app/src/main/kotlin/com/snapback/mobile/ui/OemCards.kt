package com.snapback.mobile.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

enum class Oem(val displayName: String) {
    Samsung("Samsung"),
    Xiaomi("Xiaomi"),
    OnePlus("OnePlus"),
    Generic("this device");

    companion object {
        fun fromManufacturer(m: String): Oem {
            val lower = m.lowercase()
            return when {
                "samsung" in lower -> Samsung
                "xiaomi" in lower || "redmi" in lower || "poco" in lower -> Xiaomi
                "oneplus" in lower -> OnePlus
                else -> Generic
            }
        }

        fun current(): Oem = fromManufacturer(Build.MANUFACTURER ?: "")
    }
}

object OemInstructions {
    fun textFor(oem: Oem): String = when (oem) {
        Oem.Samsung -> "Settings → Apps → SnapBack Mobile → Battery → Unrestricted."
        Oem.Xiaomi  -> "Settings → Apps → SnapBack Mobile → Battery saver → No restrictions. Also enable Autostart."
        Oem.OnePlus -> "Settings → Apps → SnapBack Mobile → Battery → Unrestricted."
        Oem.Generic -> "Disable battery optimisation for SnapBack Mobile so the foreground service survives doze."
    }

    fun deepLinkIntent(context: Context, oem: Oem): Intent? {
        return when (oem) {
            Oem.Generic, Oem.Samsung, Oem.OnePlus -> Intent(
                Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
            )
            Oem.Xiaomi -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
        }
    }
}
