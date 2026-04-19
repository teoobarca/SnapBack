package com.snapback.mobile.protocol

import org.junit.Assert.*
import org.junit.Test

class NonceCacheTest {
    @Test fun acceptsFirstOccurrence() {
        val c = NonceCache(capacity = 8, ttlSeconds = 600.0)
        assertTrue(c.tryAdd("n1", at = 100.0))
    }

    @Test fun rejectsDuplicateWithinTTL() {
        val c = NonceCache(8, 600.0)
        c.tryAdd("n1", 100.0)
        assertFalse(c.tryAdd("n1", 101.0))
    }

    @Test fun acceptsAfterTTL() {
        val c = NonceCache(8, 600.0)
        c.tryAdd("n1", 100.0)
        assertTrue(c.tryAdd("n1", 701.0))
    }

    @Test fun evictsOldestOverCapacity() {
        val c = NonceCache(capacity = 2, ttlSeconds = 600.0)
        c.tryAdd("a", 100.0)
        c.tryAdd("b", 101.0)
        c.tryAdd("c", 102.0)
        assertTrue(c.tryAdd("a", 103.0))
    }
}
