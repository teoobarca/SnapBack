package com.snapback.mobile.protocol

import org.junit.Assert.assertEquals
import org.junit.Test

class CanonicalJsonTest {
    private fun encode(v: JsonValue) = String(CanonicalJson.encode(v), Charsets.UTF_8)

    @Test fun objectKeysSortedAlphabetically() {
        val v = JsonValue.Obj(listOf("b" to JsonValue.Integer(2), "a" to JsonValue.Integer(1)))
        assertEquals("""{"a":1,"b":2}""", encode(v))
    }

    @Test fun emptyObject() {
        assertEquals("{}", encode(JsonValue.Obj(emptyList())))
    }

    @Test fun stringEscaping() {
        val v = JsonValue.Str("a\"b\\c\n")
        assertEquals("\"a\\\"b\\\\c\\n\"", encode(v))
    }

    @Test fun integerNoFraction() {
        assertEquals("0", encode(JsonValue.Integer(0)))
    }

    @Test fun booleansAndNull() {
        assertEquals("true", encode(JsonValue.Bool(true)))
        assertEquals("false", encode(JsonValue.Bool(false)))
        assertEquals("null", encode(JsonValue.Null))
    }

    @Test fun controlCharsAsUxxxxLowercase() {
        val v = JsonValue.Str("\u0001")
        assertEquals("\"\\u0001\"", encode(v))
    }

    @Test fun nestedObjectSortsRecursively() {
        val inner = JsonValue.Obj(listOf("y" to JsonValue.Integer(1), "x" to JsonValue.Integer(2)))
        val outer = JsonValue.Obj(listOf("b" to inner, "a" to JsonValue.Integer(0)))
        assertEquals("""{"a":0,"b":{"x":2,"y":1}}""", encode(outer))
    }
}
