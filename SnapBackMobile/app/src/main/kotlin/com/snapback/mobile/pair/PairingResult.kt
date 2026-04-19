package com.snapback.mobile.pair

import android.net.Uri

data class PairingResult(val tokenHex: String, val deskName: String) {
    val token: ByteArray get() {
        val out = ByteArray(32)
        for (i in 0 until 32) {
            val hi = tokenHex[2 * i].digitToInt(16)
            val lo = tokenHex[2 * i + 1].digitToInt(16)
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    companion object {
        fun parse(url: String): PairingResult? {
            val uri = try { Uri.parse(url) } catch (e: Exception) { return null }
            if (uri.scheme != "snapback-pair") return null
            if (uri.host != "v1") return null
            if (uri.getQueryParameter("v") != "1") return null
            val token = uri.getQueryParameter("token") ?: return null
            if (token.length != 64) return null
            if (!token.all { it in '0'..'9' || it in 'a'..'f' }) return null
            val desk = uri.getQueryParameter("desk") ?: return null
            return PairingResult(token, desk)
        }
    }
}
