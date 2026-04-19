package com.snapback.mobile.net

import com.snapback.mobile.protocol.*
import java.net.Socket

class TestFakeMac(private val host: String, private val port: Int, private val secret: ByteArray) {
    private lateinit var socket: Socket
    val received = mutableListOf<String>()

    fun connect() {
        socket = Socket(host, port)
    }

    fun sendHello() = send(ProtocolMessageType.Hello,
        listOf("app_version" to JsonValue.Str("test"),
               "peer_name" to JsonValue.Str("TestFakeMac")))

    fun send(type: ProtocolMessageType, payload: List<Pair<String, JsonValue>> = emptyList()) {
        val nonce = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it.toInt() and 0xFF) }
        val msg = ProtocolMessage(
            version = 1, type = type,
            timestamp = System.currentTimeMillis() / 1000,
            nonceHex = nonce, payload = payload
        )
        rawSend(MessageCodec.encodeSignedLine(msg, ProtocolDirection.ClientToServer, secret))
    }

    fun rawSend(line: String) {
        socket.getOutputStream().write(line.toByteArray(Charsets.UTF_8))
        socket.getOutputStream().flush()
    }

    fun startReceiver() {
        Thread {
            try {
                val reader = socket.getInputStream().bufferedReader(Charsets.UTF_8)
                while (true) {
                    val line = reader.readLine() ?: break
                    val (msg, hmac) = MessageCodec.decodeLine(line + "\n")
                    if (MessageCodec.verify(msg, ProtocolDirection.ServerToClient, hmac, secret)) {
                        synchronized(received) { received.add(msg.type.wire) }
                    }
                }
            } catch (e: Exception) { /* connection closed */ }
        }.apply { isDaemon = true; start() }
    }

    fun close() { try { socket.close() } catch (_: Exception) {} }
}
