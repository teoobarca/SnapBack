package com.snapback.mobile.protocol

data class ProtocolMessage(
    val version: Int,
    val type: ProtocolMessageType,
    val timestamp: Long,
    val nonceHex: String,
    val payload: List<Pair<String, JsonValue>> = emptyList()
)
