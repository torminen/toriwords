package com.toriwords.core

import java.security.MessageDigest
import kotlin.random.Random

/** A record ID: 16 bytes, ordered as unsigned bytes. Text form is lowercase hyphenated. */
data class ToriId(
    /** Bytes 0–7 and 8–15, big-endian, so unsigned integer order equals unsigned byte order. */
    val high: ULong,
    val low: ULong,
) : Comparable<ToriId> {

    val bytes: ByteArray
        get() = ByteArray(16) { i ->
            val word = if (i < 8) high else low
            (word shr (56 - 8 * (i % 8))).toByte()
        }

    override fun compareTo(other: ToriId): Int =
        if (high != other.high) high.compareTo(other.high) else low.compareTo(other.low)

    override fun toString(): String {
        val hex = high.toString(16).padStart(16, '0') + low.toString(16).padStart(16, '0')
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
            "${hex.substring(16, 20)}-${hex.substring(20)}"
    }

    companion object {
        fun fromBytes(bytes: ByteArray): ToriId {
            require(bytes.size == 16) { "ToriId needs 16 bytes" }
            var h = 0UL
            var l = 0UL
            for (i in 0 until 16) {
                val b = bytes[i].toUByte().toULong()
                if (i < 8) h = (h shl 8) or b else l = (l shl 8) or b
            }
            return ToriId(h, l)
        }

        /** Parses `8-4-4-4-12` hex, either case; null otherwise. */
        fun parse(text: String): ToriId? {
            val parts = text.split('-')
            if (parts.map { it.length } != listOf(8, 4, 4, 4, 12)) return null
            val hex = parts.joinToString("")
            if (!hex.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
            return ToriId(hex.substring(0, 16).toULong(16), hex.substring(16).toULong(16))
        }

        /** UUIDv7 (RFC 9562): 48-bit Unix ms ‖ ver 7 ‖ 12-bit `randA` ‖ variant 0b10 ‖ 62-bit `randB` (extra bits masked). */
        fun v7(unixMs: Long, randA: Int, randB: ULong): ToriId {
            require(unixMs >= 0 && unixMs < (1L shl 48))
            val h = (unixMs.toULong() shl 16) or 0x7000UL or (randA and 0x0FFF).toULong()
            return ToriId(h, 0x8000_0000_0000_0000UL or (randB and 0x3FFF_FFFF_FFFF_FFFFUL))
        }

        /** A new random UUIDv7; time and randomness are injected. */
        fun v7(unixMs: Long, random: Random): ToriId =
            v7(unixMs, random.nextInt(0, 0x1000), random.nextLong().toULong())

        /** The Toriwords namespace (fixed forever). */
        val namespace: ToriId = parse("6f1c2a4e-3b7d-5e59-9a0c-5d8e7f2b1c34")!!

        /** UUIDv5 (SHA-1) of a UTF-8 name under the Toriwords namespace. */
        fun v5(name: String): ToriId {
            val sha1 = MessageDigest.getInstance("SHA-1")
            sha1.update(namespace.bytes)
            val b = sha1.digest(name.toByteArray(Charsets.UTF_8)).copyOf(16)
            b[6] = ((b[6].toInt() and 0x0F) or 0x50).toByte()
            b[8] = ((b[8].toInt() and 0x3F) or 0x80).toByte()
            return fromBytes(b)
        }

        fun languagePair(native: String, target: String): ToriId = v5("pair:$native:$target")
        val settings: ToriId = v5("settings")
        fun card(entry: ToriId, direction: CardDirection): ToriId = v5("card:$entry:${direction.wire}")
        fun source(urlKey: String): ToriId = v5("source:$urlKey")
        fun entryTag(entry: ToriId, tag: ToriId): ToriId = v5("entrytag:$entry:$tag")
        fun autoSense(entry: ToriId, ordinal: Int): ToriId = v5("autosense:$entry:$ordinal")
    }
}

/** Card direction; `wire` is the synced name. Declaration order is the queue order. */
enum class CardDirection(val wire: String) {
    RECOGNITION("recognition"), RECALL("recall"), CLOZE("cloze");

    companion object {
        fun fromWire(value: String): CardDirection? = entries.firstOrNull { it.wire == value }
    }
}
