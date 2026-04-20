package com.snapback.mobile.net

import com.snapback.mobile.protocol.*
import kotlinx.coroutines.*
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * TCP server that receives signed messages from the paired Mac and dispatches
 * the valid ones through `onMessage`. Replies to hello/heartbeat/resync inline.
 *
 * Replay protection: per-secret NonceCache, 10 min TTL. Timestamp drift ±30 s.
 */
class MessageServer(
    private val secret: ByteArray,
    val port: Int,
    private val onMessage: (ProtocolMessage) -> Unit,
    val holdStateProvider: () -> Boolean = { false }
) {
    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val nonceCache = NonceCache(capacity = 1024, ttlSeconds = 600.0)

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val s = ServerSocket(port)
        serverSocket = s
        scope.launch {
            while (running.get()) {
                val client = try { s.accept() } catch (e: Exception) { break }
                scope.launch { handle(client) }
            }
        }
    }

    fun stop() {
        running.set(false)
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        scope.cancel()
    }

    private suspend fun handle(socket: Socket) {
        try {
            val reader = socket.getInputStream().bufferedReader(Charsets.UTF_8)
            val writer = socket.getOutputStream()
            while (true) {
                val line = reader.readLine() ?: break
                val (msg, hmac) = try { MessageCodec.decodeLine(line + "\n") }
                                   catch (e: Exception) { continue }
                if (!MessageCodec.verify(msg, ProtocolDirection.ClientToServer, hmac, secret)) continue
                val now = System.currentTimeMillis() / 1000.0
                if (kotlin.math.abs(now - msg.timestamp) > 30) continue
                if (!nonceCache.tryAdd(msg.nonceHex, now)) continue

                onMessage(msg)

                when (msg.type) {
                    ProtocolMessageType.Hello -> reply(writer, ProtocolMessageType.Ack, emptyList())
                    ProtocolMessageType.Heartbeat,
                    ProtocolMessageType.Resync -> reply(
                        writer, ProtocolMessageType.Pong,
                        listOf("hold" to JsonValue.Bool(holdStateProvider()))
                    )
                    else -> {}
                }
            }
        } catch (e: Exception) {
            // Dropped connection
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun reply(writer: java.io.OutputStream, type: ProtocolMessageType,
                      payload: List<Pair<String, JsonValue>>) {
        val nonce = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it.toInt() and 0xFF) }
        val msg = ProtocolMessage(
            1, type, System.currentTimeMillis() / 1000, nonce, payload
        )
        val line = MessageCodec.encodeSignedLine(msg, ProtocolDirection.ServerToClient, secret)
        writer.write(line.toByteArray(Charsets.UTF_8))
        writer.flush()
    }
}
