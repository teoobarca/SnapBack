package com.snapback.mobile.protocol

import org.junit.Assert.*
import org.junit.Test

class MessageCodecTest {
    private val secret = ByteArray(32) { 0x42 }

    @Test fun signingDomainHasDirectionFirstAndNullSeparators() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Attention, timestamp = 1_734_556_677L,
            nonceHex = "0".repeat(32),
            payload = listOf("hook" to JsonValue.Str("Stop"))
        )
        val domain = MessageCodec.signingDomain(msg, ProtocolDirection.ClientToServer)
        val expected = ("c2s\u0000" + "1\u0000" + "attention\u0000" +
            "1734556677\u0000" + "0".repeat(32) + "\u0000" + "{\"hook\":\"Stop\"}")
            .toByteArray(Charsets.UTF_8)
        assertArrayEquals(expected, domain)
    }

    @Test fun emptyPayloadSerializesAsOpenClose() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Resume, timestamp = 100L,
            nonceHex = "1".repeat(32), payload = emptyList()
        )
        val domain = MessageCodec.signingDomain(msg, ProtocolDirection.ClientToServer)
        assertTrue(String(domain, Charsets.UTF_8).endsWith("\u0000{}"))
    }

    @Test fun signProducesLowercase64HexChars() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Heartbeat, timestamp = 1L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        assertEquals(64, sig.length)
        assertTrue(sig.all { it in "0123456789abcdef" })
    }

    @Test fun verifyAcceptsCorrectSignature() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Hello, timestamp = 17L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        assertTrue(MessageCodec.verify(msg, ProtocolDirection.ClientToServer, sig, secret))
    }

    @Test fun verifyRejectsOnDirectionMismatch() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Hello, timestamp = 17L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        assertFalse(MessageCodec.verify(msg, ProtocolDirection.ServerToClient, sig, secret))
    }

    @Test fun verifyRejectsOnTamperedField() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Attention, timestamp = 17L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        val tampered = msg.copy(timestamp = 18L)
        assertFalse(MessageCodec.verify(tampered, ProtocolDirection.ClientToServer, sig, secret))
    }

    @Test fun nonceValidatorAcceptsExactly32Lowercase() {
        assertTrue(MessageCodec.isValidNonceHex("0".repeat(32)))
        assertTrue(MessageCodec.isValidNonceHex("abcdef0123456789abcdef0123456789"))
    }

    @Test fun nonceValidatorRejectsUppercase() {
        assertFalse(MessageCodec.isValidNonceHex("A".repeat(32)))
    }

    @Test fun nonceValidatorRejectsWrongLength() {
        assertFalse(MessageCodec.isValidNonceHex("0".repeat(31)))
        assertFalse(MessageCodec.isValidNonceHex("0".repeat(33)))
    }

    @Test fun hexParseStrict() {
        assertArrayEquals(byteArrayOf(0x00, 0x01, 0xFF.toByte()), MessageCodec.hexToBytes("0001ff"))
        assertNull(MessageCodec.hexToBytes("0001 ff"))
        assertNull(MessageCodec.hexToBytes("0001FF"))
        assertNull(MessageCodec.hexToBytes("0001f"))
    }

    @Test fun roundTripSignedMessage() {
        val secret2 = ByteArray(32) { 0xAB.toByte() }
        val original = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Attention, timestamp = 1_734_556_677L,
            nonceHex = "a".repeat(32),
            payload = listOf("hook" to JsonValue.Str("PermissionRequest"))
        )
        val line = MessageCodec.encodeSignedLine(original, ProtocolDirection.ClientToServer, secret2)
        assertTrue(line.endsWith("\n"))
        val (decoded, hmac) = MessageCodec.decodeLine(line)
        assertEquals(original.type, decoded.type)
        assertEquals(original.timestamp, decoded.timestamp)
        assertEquals(original.nonceHex, decoded.nonceHex)
        assertTrue(MessageCodec.verify(decoded, ProtocolDirection.ClientToServer, hmac, secret2))
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsMissingHmac() {
        val json = """{"v":1,"type":"resume","ts":1,"nonce":"${"0".repeat(32)}","payload":{}}""" + "\n"
        MessageCodec.decodeLine(json)
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsUnknownType() {
        val json = """{"v":1,"type":"bogus","ts":1,"nonce":"${"0".repeat(32)}","payload":{},"hmac":"x"}""" + "\n"
        MessageCodec.decodeLine(json)
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsUppercaseNonce() {
        val bad = "A".repeat(32)
        val json = """{"v":1,"type":"resume","ts":1,"nonce":"$bad","payload":{},"hmac":"${"0".repeat(64)}"}""" + "\n"
        MessageCodec.decodeLine(json)
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsUnknownVersion() {
        val json = """{"v":2,"type":"resume","ts":1,"nonce":"${"0".repeat(32)}","payload":{},"hmac":"${"0".repeat(64)}"}""" + "\n"
        MessageCodec.decodeLine(json)
    }
}
