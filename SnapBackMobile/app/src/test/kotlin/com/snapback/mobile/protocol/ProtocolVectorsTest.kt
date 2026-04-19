package com.snapback.mobile.protocol

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class ProtocolVectorsTest {
    @Test fun allVectorsMatchPrecomputedHmacs() {
        val fixtureFile = File(System.getProperty("user.dir"), "../../tests/protocol-vectors.json")
            .also { require(it.exists()) { "fixture missing: ${it.absolutePath}" } }
        val json = JSONObject(fixtureFile.readText())
        val secretHex = json.getString("secret_hex")
        val secret = MessageCodec.hexToBytes(secretHex)!!
        val vectors = json.getJSONArray("vectors")
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val name = v.getString("name")
            val direction = ProtocolDirection.fromWire(v.getString("direction"))!!
            val m = v.getJSONObject("message")
            val payload = m.getJSONObject("payload")
            val pairs = payload.keys().asSequence().sorted().toList().map { k ->
                k to jsonAnyToValue(payload.get(k))
            }
            val msg = ProtocolMessage(
                version = m.getInt("v"),
                type = ProtocolMessageType.fromWire(m.getString("type"))!!,
                timestamp = m.getLong("ts"),
                nonceHex = m.getString("nonce"),
                payload = pairs
            )
            val actual = MessageCodec.sign(msg, direction, secret)
            val expected = v.optString("expected_hmac_hex", "")
            assertEquals("vector '$name' HMAC mismatch", expected, actual)
        }
    }

    private fun jsonAnyToValue(a: Any): JsonValue = when (a) {
        is String -> JsonValue.Str(a)
        is Int -> JsonValue.Integer(a.toLong())
        is Long -> JsonValue.Integer(a)
        is Double -> JsonValue.Floating(a)
        is Boolean -> JsonValue.Bool(a)
        JSONObject.NULL -> JsonValue.Null
        is JSONObject -> JsonValue.Obj(
            a.keys().asSequence().sorted().toList().map { it to jsonAnyToValue(a.get(it)) }
        )
        is JSONArray -> JsonValue.Arr((0 until a.length()).map { jsonAnyToValue(a.get(it)) })
        else -> throw IllegalArgumentException("unsupported fixture value: ${a::class}")
    }
}
