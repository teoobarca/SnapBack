package com.snapback.mobile.protocol

class NonceCache(private val capacity: Int, private val ttlSeconds: Double) {
    private data class Entry(val nonce: String, val insertedAt: Double)
    private val entries = ArrayDeque<Entry>()

    @Synchronized
    fun tryAdd(nonce: String, at: Double): Boolean {
        while (entries.isNotEmpty() && at - entries.first().insertedAt > ttlSeconds) {
            entries.removeFirst()
        }
        if (entries.any { it.nonce == nonce }) return false
        entries.addLast(Entry(nonce, at))
        while (entries.size > capacity) entries.removeFirst()
        return true
    }
}
