package com.snapback.mobile.security

/**
 * Secret-byte persistence interface. Production uses Android Keystore;
 * tests use InMemoryTokenStore to bypass Keystore's Robolectric quirks.
 */
interface TokenStore {
    fun read(): ByteArray?
    fun write(token: ByteArray)
    fun delete()
}

class InMemoryTokenStore : TokenStore {
    private var value: ByteArray? = null
    override fun read(): ByteArray? = value?.copyOf()
    override fun write(token: ByteArray) { value = token.copyOf() }
    override fun delete() { value = null }
}
