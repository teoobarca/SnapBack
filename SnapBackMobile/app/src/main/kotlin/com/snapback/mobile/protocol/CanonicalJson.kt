package com.snapback.mobile.protocol

object CanonicalJson {
    fun encode(value: JsonValue): ByteArray {
        val sb = StringBuilder()
        append(value, sb)
        return sb.toString().toByteArray(Charsets.UTF_8)
    }

    private fun append(value: JsonValue, sb: StringBuilder) {
        when (value) {
            is JsonValue.Null       -> sb.append("null")
            is JsonValue.Bool       -> sb.append(if (value.value) "true" else "false")
            is JsonValue.Integer    -> sb.append(value.value.toString())
            is JsonValue.Floating   -> sb.append(value.value.toString())
            is JsonValue.Str        -> appendString(value.value, sb)
            is JsonValue.Arr -> {
                sb.append('[')
                value.items.forEachIndexed { i, v ->
                    if (i > 0) sb.append(',')
                    append(v, sb)
                }
                sb.append(']')
            }
            is JsonValue.Obj -> {
                sb.append('{')
                value.pairs.sortedBy { it.first }.forEachIndexed { i, (k, v) ->
                    if (i > 0) sb.append(',')
                    appendString(k, sb)
                    sb.append(':')
                    append(v, sb)
                }
                sb.append('}')
            }
        }
    }

    private fun appendString(s: String, sb: StringBuilder) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"'      -> sb.append("\\\"")
                '\\'     -> sb.append("\\\\")
                '\b'     -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                '\n'     -> sb.append("\\n")
                '\r'     -> sb.append("\\r")
                '\t'     -> sb.append("\\t")
                else -> {
                    if (c.code < 0x20) {
                        sb.append("\\u%04x".format(c.code))
                    } else {
                        sb.append(c)
                    }
                }
            }
        }
        sb.append('"')
    }
}
