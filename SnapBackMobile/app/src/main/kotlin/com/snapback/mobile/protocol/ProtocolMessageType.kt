package com.snapback.mobile.protocol

enum class ProtocolMessageType(val wire: String) {
    Hello("hello"),
    Ack("ack"),
    Attention("attention"),
    Resume("resume"),
    Heartbeat("heartbeat"),
    Pong("pong"),
    Resync("resync"),
    Invalidate("invalidate");

    companion object {
        fun fromWire(s: String): ProtocolMessageType? = entries.firstOrNull { it.wire == s }
    }
}
