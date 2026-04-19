package com.snapback.mobile.protocol

enum class ProtocolDirection(val wire: String) {
    ClientToServer("c2s"),
    ServerToClient("s2c");

    companion object {
        fun fromWire(s: String): ProtocolDirection? = entries.firstOrNull { it.wire == s }
    }
}
