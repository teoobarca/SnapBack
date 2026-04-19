package com.snapback.mobile.security

import org.junit.Assert.*
import org.junit.Test

class InMemoryTokenStoreTest {
    @Test fun readReturnsNullWhenAbsent() {
        assertNull(InMemoryTokenStore().read())
    }

    @Test fun writeThenReadRoundTrip() {
        val s = InMemoryTokenStore()
        val data = ByteArray(32) { it.toByte() }
        s.write(data)
        assertArrayEquals(data, s.read())
    }

    @Test fun deleteClears() {
        val s = InMemoryTokenStore()
        s.write(ByteArray(4))
        s.delete()
        assertNull(s.read())
    }

    @Test fun readReturnsCopyNotReference() {
        val s = InMemoryTokenStore()
        val data = byteArrayOf(1, 2, 3)
        s.write(data)
        val out = s.read()!!
        out[0] = 99
        assertArrayEquals(byteArrayOf(1, 2, 3), s.read())
    }
}
