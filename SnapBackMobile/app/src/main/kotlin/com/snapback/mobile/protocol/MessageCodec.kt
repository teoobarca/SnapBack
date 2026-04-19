package com.snapback.mobile.protocol

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object MessageCodec {
    fun sign(
        message: ProtocolMessage,
        direction: ProtocolDirection,
        secret: ByteArray
    ): String {
        require(isValidNonceHex(message.nonceHex)) {
            "nonceHex must be exactly 32 lowercase hex chars"
        }
        val domain = signingDomain(message, direction)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return bytesToHex(mac.doFinal(domain))
    }

    fun verify(
        message: ProtocolMessage,
        direction: ProtocolDirection,
        hmacHex: String,
        secret: ByteArray
    ): Boolean {
        val expected = hexToBytes(hmacHex) ?: return false
        val domain = signingDomain(message, direction)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val actual = mac.doFinal(domain)
        if (actual.size != expected.size) return false
        var diff = 0
        for (i in actual.indices) diff = diff or (actual[i].toInt() xor expected[i].toInt())
        return diff == 0
    }

    fun signingDomain(message: ProtocolMessage, direction: ProtocolDirection): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        out.write(direction.wire.toByteArray(Charsets.UTF_8))
        out.write(0)
        out.write(message.version.toString().toByteArray(Charsets.UTF_8))
        out.write(0)
        out.write(message.type.wire.toByteArray(Charsets.UTF_8))
        out.write(0)
        out.write(message.timestamp.toString().toByteArray(Charsets.UTF_8))
        out.write(0)
        out.write(message.nonceHex.toByteArray(Charsets.UTF_8))
        out.write(0)
        out.write(CanonicalJson.encode(JsonValue.Obj(message.payload)))
        return out.toByteArray()
    }

    fun isValidNonceHex(s: String): Boolean {
        if (s.length != 32) return false
        return s.all { it in '0'..'9' || it in 'a'..'f' }
    }

    fun hexToBytes(s: String): ByteArray? {
        if (s.length % 2 != 0) return null
        val out = ByteArray(s.length / 2)
        for (i in out.indices) {
            val hi = hexNibble(s[2 * i]) ?: return null
            val lo = hexNibble(s[2 * i + 1]) ?: return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    private fun hexNibble(c: Char): Int? = when (c) {
        in '0'..'9' -> c.code - '0'.code
        in 'a'..'f' -> c.code - 'a'.code + 10
        else -> null
    }

    private fun bytesToHex(b: ByteArray): String {
        val sb = StringBuilder(b.size * 2)
        for (byte in b) sb.append("%02x".format(byte.toInt() and 0xFF))
        return sb.toString()
    }

    fun encodeSignedLine(
        message: ProtocolMessage,
        direction: ProtocolDirection,
        secret: ByteArray
    ): String {
        require(isValidNonceHex(message.nonceHex))
        val hmac = sign(message, direction, secret)
        val body = JsonValue.Obj(listOf(
            "hmac" to JsonValue.Str(hmac),
            "nonce" to JsonValue.Str(message.nonceHex),
            "payload" to JsonValue.Obj(message.payload),
            "ts" to JsonValue.Integer(message.timestamp),
            "type" to JsonValue.Str(message.type.wire),
            "v" to JsonValue.Integer(message.version.toLong())
        ))
        val bytes = CanonicalJson.encode(body)
        return String(bytes, Charsets.UTF_8) + "\n"
    }

    fun decodeLine(line: String): Pair<ProtocolMessage, String> {
        val trimmed = if (line.endsWith("\n")) line.dropLast(1) else line
        val obj = try { JSONTokener(trimmed).nextValue() as? JSONObject }
                  catch (e: Exception) { null }
                  ?: throw MessageCodecException("not a JSON object")

        val v = obj.optInt("v", -1)
        if (v == -1) throw MessageCodecException("missing v")
        if (v != 1) throw MessageCodecException("unknown version $v")

        val typeStr = obj.optString("type", "")
        val type = ProtocolMessageType.fromWire(typeStr)
            ?: throw MessageCodecException("unknown type: $typeStr")

        val ts = obj.opt("ts") as? Number
            ?: throw MessageCodecException("missing ts")
        val tsLong = ts.toLong()

        val nonce = obj.optString("nonce", "")
        if (!isValidNonceHex(nonce)) throw MessageCodecException("invalid nonce")

        val hmac = obj.optString("hmac", "")
        if (hmac.isEmpty()) throw MessageCodecException("missing hmac")

        val payloadJson = obj.optJSONObject("payload") ?: JSONObject()
        val payload = payloadJson.toPairs()

        return ProtocolMessage(v, type, tsLong, nonce, payload) to hmac
    }

    private fun JSONObject.toPairs(): List<Pair<String, JsonValue>> {
        val keys = keys().asSequence().toList().sorted()
        return keys.map { k -> k to fromJson(get(k)) }
    }

    private fun fromJson(v: Any): JsonValue = when (v) {
        is String -> JsonValue.Str(v)
        is Boolean -> JsonValue.Bool(v)
        is Int -> JsonValue.Integer(v.toLong())
        is Long -> JsonValue.Integer(v)
        is Double -> JsonValue.Floating(v)
        is Float -> JsonValue.Floating(v.toDouble())
        JSONObject.NULL -> JsonValue.Null
        is JSONObject -> JsonValue.Obj(v.toPairs())
        is JSONArray -> JsonValue.Arr((0 until v.length()).map { fromJson(v.get(it)) })
        else -> throw MessageCodecException("unsupported JSON type: ${v::class}")
    }
}

class MessageCodecException(message: String) : Exception(message)
