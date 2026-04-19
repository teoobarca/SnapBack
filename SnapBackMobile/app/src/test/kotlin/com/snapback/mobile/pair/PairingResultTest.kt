package com.snapback.mobile.pair

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PairingResultTest {
    @Test fun parseGoodURL() {
        val url = "snapback-pair://v1?token=" + "a".repeat(64) + "&desk=Hamper%27s%20MBP&v=1"
        val r = PairingResult.parse(url)
        assertNotNull(r)
        r!!
        assertEquals("a".repeat(64), r.tokenHex)
        assertEquals("Hamper's MBP", r.deskName)
    }

    @Test fun rejectsWrongScheme() {
        assertNull(PairingResult.parse("http://example.com/?token=" + "a".repeat(64)))
    }

    @Test fun rejectsWrongVersion() {
        val url = "snapback-pair://v2?token=" + "a".repeat(64) + "&desk=X&v=2"
        assertNull(PairingResult.parse(url))
    }

    @Test fun rejectsBadTokenLength() {
        val url = "snapback-pair://v1?token=" + "a".repeat(63) + "&desk=X&v=1"
        assertNull(PairingResult.parse(url))
    }

    @Test fun rejectsUppercaseTokenHex() {
        val url = "snapback-pair://v1?token=" + "A".repeat(64) + "&desk=X&v=1"
        assertNull(PairingResult.parse(url))
    }
}
