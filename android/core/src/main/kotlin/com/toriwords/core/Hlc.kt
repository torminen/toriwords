package com.toriwords.core

/** One hybrid logical clock value. */
data class HlcTimestamp(
    val ms: Long,
    val counter: Int,
    /** First 64 bits of the Device ID. */
    val node: ULong,
) : Comparable<HlcTimestamp> {

    override fun compareTo(other: HlcTimestamp): Int = compareValuesBy(this, other, { it.ms }, { it.counter }, { it.node })

    /** `ms` (12 hex) ‖ `counter` (4 hex) ‖ `node` (16 hex); string order = clock order. */
    override fun toString(): String =
        ms.toString(16).padStart(12, '0') + counter.toString(16).padStart(4, '0') + node.toString(16).padStart(16, '0')

    companion object {
        /** Parses the 32-char lowercase hex form; null otherwise. */
        fun parse(text: String): HlcTimestamp? {
            if (text.length != 32 || !text.all { it in '0'..'9' || it in 'a'..'f' }) return null
            return HlcTimestamp(text.substring(0, 12).toLong(16), text.substring(12, 16).toInt(16), text.substring(16).toULong(16))
        }
    }
}

/** Persisted HLC state `{ms, counter}`, with the clock-ahead reset against the last server time. */
data class HlcState(var ms: Long = 0, var counter: Int = 0) {

    /** Local write: returns the clock for the written field. */
    fun localWrite(now: Long, node: ULong): HlcTimestamp {
        if (now > ms) {
            ms = now
            counter = 0
        } else {
            bump(counter + 1)
        }
        return HlcTimestamp(ms, counter, node)
    }

    /** Receive a pulled clock. A remote clock more than 24 h ahead of `now` is not adopted. */
    fun receive(remote: HlcTimestamp, now: Long) {
        if (remote.ms - now > DAY_MS) return
        val newMs = maxOf(ms, remote.ms, now)
        val c = when {
            newMs == ms && newMs == remote.ms -> maxOf(counter, remote.counter) + 1
            newMs == ms -> counter + 1
            newMs == remote.ms -> remote.counter + 1
            else -> 0
        }
        ms = newMs
        bump(c)
    }

    /**
     * Clock-ahead recovery before push: if the clock is more than 1 h ahead of the last server time, reset it and
     * re-stamp the pending fields in outbox order. Returns the new clocks, or null when no reset is needed.
     */
    fun recoverIfAhead(lastServerTime: Long, now: Long, node: ULong, pendingFields: Int): List<HlcTimestamp>? {
        if (ms - lastServerTime <= HOUR_MS) return null
        ms = maxOf(lastServerTime, now)
        counter = 0
        return List(pendingFields) { localWrite(now, node) }
    }

    private fun bump(c: Int) {
        if (c > 0xFFFF) {
            ms += 1
            counter = 0
        } else {
            counter = c
        }
    }

    companion object {
        const val DAY_MS = 86_400_000L
        const val HOUR_MS = 3_600_000L

        /** Retired server rule (kept because `hlc/receive.json` still pins it): a clock > 1 h ahead is `clock_skew`. */
        fun serverAccepts(clock: HlcTimestamp, serverTime: Long): Boolean = clock.ms - serverTime <= HOUR_MS
    }
}
