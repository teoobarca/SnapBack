package com.snapback.mobile.protocol

sealed class JsonValue {
    data class Str(val value: String) : JsonValue()
    data class Integer(val value: Long) : JsonValue()
    data class Floating(val value: Double) : JsonValue()
    data class Bool(val value: Boolean) : JsonValue()
    data object Null : JsonValue()
    data class Arr(val items: List<JsonValue>) : JsonValue()
    data class Obj(val pairs: List<Pair<String, JsonValue>>) : JsonValue()
}
