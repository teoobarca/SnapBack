package com.snapback.mobile.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Persists the 32-byte pair token. Token is AES-GCM encrypted under a
 * hardware-backed key (when available) whose key material never leaves the
 * Keystore. The ciphertext + IV lives in a private SharedPreferences file.
 */
class KeystoreTokenStore(private val context: Context) : TokenStore {

    override fun read(): ByteArray? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ivHex = prefs.getString(KEY_IV, null) ?: return null
        val ctHex = prefs.getString(KEY_CIPHERTEXT, null) ?: return null
        val iv = ivHex.hexToBytesOrNull() ?: return null
        val ct = ctHex.hexToBytesOrNull() ?: return null
        val secretKey = getOrCreateKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        return try { cipher.doFinal(ct) } catch (e: Exception) { null }
    }

    override fun write(token: ByteArray) {
        val secretKey = getOrCreateKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val ct = cipher.doFinal(token)
        val iv = cipher.iv
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            putString(KEY_IV, iv.toHex())
            putString(KEY_CIPHERTEXT, ct.toHex())
        }.apply()
    }

    override fun delete() {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false)
                .build()
        )
        return gen.generateKey()
    }

    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    private fun String.hexToBytesOrNull(): ByteArray? {
        if (length % 2 != 0) return null
        val out = ByteArray(length / 2)
        for (i in out.indices) {
            val hi = digit(this[2 * i]) ?: return null
            val lo = digit(this[2 * i + 1]) ?: return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }
    private fun digit(c: Char): Int? = when (c) {
        in '0'..'9' -> c.code - '0'.code
        in 'a'..'f' -> c.code - 'a'.code + 10
        else -> null
    }

    companion object {
        private const val PREFS = "com.snapback.mobile.token"
        private const val KEY_IV = "iv"
        private const val KEY_CIPHERTEXT = "ct"
        private const val KEY_ALIAS = "com.snapback.mobile.pair-token"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
