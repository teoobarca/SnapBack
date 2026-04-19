package com.snapback.mobile.net

import com.snapback.mobile.protocol.*
import org.junit.Assert.*
import org.junit.Test
import java.net.ServerSocket

class MessageServerTest {
    private val secret = ByteArray(32) { 0x42 }

    @Test fun acceptsHelloAndRepliesAck() {
        val port = ServerSocket(0).use { it.localPort }
        val events = mutableListOf<ProtocolMessage>()
        val server = MessageServer(secret, port) { events.add(it) }
        server.start()
        try {
            val mac = TestFakeMac("127.0.0.1", port, secret)
            mac.connect()
            mac.startReceiver()
            mac.sendHello()
            waitUntil(3000) { events.any { it.type == ProtocolMessageType.Hello } }
            waitUntil(3000) { mac.received.contains("ack") }
            mac.close()
            assertTrue(events.any { it.type == ProtocolMessageType.Hello })
            assertTrue(mac.received.contains("ack"))
        } finally {
            server.stop()
        }
    }

    @Test fun rejectsTamperedHmac() {
        val port = ServerSocket(0).use { it.localPort }
        val events = mutableListOf<ProtocolMessage>()
        val server = MessageServer(secret, port) { events.add(it) }
        server.start()
        try {
            val badLine = """{"v":1,"type":"attention","ts":1,"nonce":"${"0".repeat(32)}",""" +
                """"payload":{"hook":"Stop"},"hmac":"${"0".repeat(64)}"}""" + "\n"
            java.net.Socket("127.0.0.1", port).use { s ->
                s.getOutputStream().write(badLine.toByteArray(Charsets.UTF_8))
                s.getOutputStream().flush()
                Thread.sleep(100)
            }
            assertTrue(events.isEmpty())
        } finally {
            server.stop()
        }
    }

    @Test fun rejectsReplayedNonce() {
        val port = ServerSocket(0).use { it.localPort }
        val events = mutableListOf<ProtocolMessage>()
        val server = MessageServer(secret, port) { events.add(it) }
        server.start()
        try {
            val mac = TestFakeMac("127.0.0.1", port, secret)
            mac.connect()
            mac.startReceiver()

            val msg = ProtocolMessage(
                1, ProtocolMessageType.Attention, System.currentTimeMillis() / 1000,
                "deadbeef".repeat(4), listOf("hook" to JsonValue.Str("Stop"))
            )
            val line = MessageCodec.encodeSignedLine(msg, ProtocolDirection.ClientToServer, secret)
            mac.rawSend(line)
            mac.rawSend(line)
            waitUntil(2000) { events.isNotEmpty() }
            Thread.sleep(200)
            assertEquals(1, events.count { it.type == ProtocolMessageType.Attention })
            mac.close()
        } finally {
            server.stop()
        }
    }

    private fun waitUntil(maxMs: Int, cond: () -> Boolean) {
        val deadline = System.currentTimeMillis() + maxMs
        while (System.currentTimeMillis() < deadline && !cond()) Thread.sleep(20)
    }
}
