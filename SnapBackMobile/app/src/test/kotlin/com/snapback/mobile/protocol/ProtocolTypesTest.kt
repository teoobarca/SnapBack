package com.snapback.mobile.protocol

import org.junit.Assert.assertEquals
import org.junit.Test

class ProtocolTypesTest {
    @Test fun directionValues() {
        assertEquals("c2s", ProtocolDirection.ClientToServer.wire)
        assertEquals("s2c", ProtocolDirection.ServerToClient.wire)
    }

    @Test fun allMessageTypesPresent() {
        val names = ProtocolMessageType.entries.map { it.wire }.toSet()
        val expected = setOf("hello", "ack", "attention", "resume",
            "heartbeat", "pong", "resync", "invalidate")
        assertEquals(expected, names)
    }

    @Test fun protocolMessageRoundtrip() {
        val msg = ProtocolMessage(
            version = 1,
            type = ProtocolMessageType.Attention,
            timestamp = 1_734_556_677L,
            nonceHex = "a".repeat(32),
            payload = listOf("hook" to JsonValue.Str("PermissionRequest"))
        )
        assertEquals(1, msg.version)
        assertEquals(ProtocolMessageType.Attention, msg.type)
    }
}
