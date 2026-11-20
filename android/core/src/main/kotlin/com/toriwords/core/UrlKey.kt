package com.toriwords.core

import com.toriwords.core.TextKey.codePoints
import com.toriwords.core.TextKey.isWhitespace
import com.toriwords.core.TextKey.lowercase
import com.toriwords.core.TextKey.nfc
import com.toriwords.core.TextKey.string

/**
 * URL key for Sources with a URL. Explicit split per code point, never a platform URL parser (they differ in IDN,
 * percent-encoding and port handling): `scheme ':' '//' [userinfo '@'] host [':' port] path ['?' query] ['#' fragment]`.
 */
object UrlKey {
    private val trackingParams = setOf("fbclid", "gclid", "yclid", "mc_eid")
    private val defaultPorts = mapOf("http" to "80", "https" to "443")

    fun of(url: String): String {
        var s = codePoints(nfc(url))
        while (s.isNotEmpty() && isWhitespace(s.first())) s = s.subList(1, s.size)
        while (s.isNotEmpty() && isWhitespace(s.last())) s = s.subList(0, s.size - 1)
        val colon = s.indexOf(':'.code)
        if (colon <= 0) return string(s)
        val scheme = lowercase(string(s.subList(0, colon)))
        val afterColon = s.subList(colon + 1, s.size)
        val defaultPort = defaultPorts[scheme]
        if (defaultPort == null || afterColon.size < 2 || afterColon[0] != '/'.code || afterColon[1] != '/'.code) {
            return string(s)
        }
        var rest = afterColon.subList(2, afterColon.size)
        rest.indexOf('#'.code).takeIf { it >= 0 }?.let { rest = rest.subList(0, it) }
        var query: List<Int>? = null
        rest.indexOf('?'.code).takeIf { it >= 0 }?.let {
            query = rest.subList(it + 1, rest.size)
            rest = rest.subList(0, it)
        }
        var authority = rest
        var path = emptyList<Int>()
        rest.indexOf('/'.code).takeIf { it >= 0 }?.let {
            authority = rest.subList(0, it)
            path = rest.subList(it, rest.size)
        }
        var userinfo = emptyList<Int>()
        authority.lastIndexOf('@'.code).takeIf { it >= 0 }?.let {
            userinfo = authority.subList(0, it + 1)
            authority = authority.subList(it + 1, authority.size)
        }
        var host = authority
        var port: String? = null
        if (host.firstOrNull() != '['.code) {
            host.lastIndexOf(':'.code).takeIf { it >= 0 }?.let {
                port = string(host.subList(it + 1, host.size))
                host = host.subList(0, it)
            }
        }
        if (port != null && (port.isEmpty() || port == defaultPort)) port = null
        val out = StringBuilder(scheme).append("://").append(string(userinfo)).append(punycodeHost(lowercase(string(host))))
        port?.let { out.append(':').append(it) }
        out.append(string(path))
        query?.let { q ->
            val utm = codePoints("utm_")
            val kept = split(q, '&'.code).filter { param ->
                val name = split(param, '='.code, maxSplits = 1)[0]
                !(name.size >= utm.size && name.subList(0, utm.size) == utm || string(name) in trackingParams)
            }
            if (!(kept.isEmpty() || (kept.size == 1 && kept[0].isEmpty()))) {
                out.append('?').append(kept.joinToString("&") { string(it) })
            }
        }
        return out.toString()
    }

    /** Split keeping empty parts (Swift `omittingEmptySubsequences: false`). */
    private fun split(s: List<Int>, separator: Int, maxSplits: Int = Int.MAX_VALUE): List<List<Int>> {
        val out = ArrayList<List<Int>>()
        var start = 0
        for (i in s.indices) {
            if (s[i] == separator && out.size < maxSplits) {
                out.add(s.subList(start, i))
                start = i + 1
            }
        }
        out.add(s.subList(start, s.size))
        return out
    }

    private fun punycodeHost(host: String): String =
        split(codePoints(host), '.'.code).joinToString(".") { label ->
            if (label.all { it < 0x80 }) string(label) else "xn--" + Punycode.encode(label)
        }
}

/** RFC 3492 Punycode encoder (only encoding is needed). */
internal object Punycode {
    private const val BASE = 36
    private const val T_MIN = 1
    private const val T_MAX = 26
    private const val SKEW = 38
    private const val DAMP = 700
    private const val INITIAL_BIAS = 72
    private const val INITIAL_N = 0x80

    fun encode(input: List<Int>): String {
        val output = StringBuilder()
        input.filter { it < 0x80 }.forEach { output.appendCodePoint(it) }
        val basicCount = output.length
        var handled = basicCount
        if (basicCount > 0) output.append('-')
        var n = INITIAL_N
        var delta = 0
        var bias = INITIAL_BIAS
        while (handled < input.size) {
            val m = input.filter { it >= n }.min()
            delta += (m - n) * (handled + 1)
            n = m
            for (c in input) {
                if (c < n) delta++
                if (c == n) {
                    var q = delta
                    var k = BASE
                    while (true) {
                        val t = if (k <= bias) T_MIN else if (k >= bias + T_MAX) T_MAX else k - bias
                        if (q < t) break
                        output.append(digit(t + (q - t) % (BASE - t)))
                        q = (q - t) / (BASE - t)
                        k += BASE
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled++
                }
            }
            delta++
            n++
        }
        return output.toString()
    }

    private fun digit(d: Int): Char = if (d < 26) 'a' + d else '0' + (d - 26)

    private fun adapt(delta: Int, numPoints: Int, first: Boolean): Int {
        var d = if (first) delta / DAMP else delta / 2
        d += d / numPoints
        var k = 0
        while (d > ((BASE - T_MIN) * T_MAX) / 2) {
            d /= BASE - T_MIN
            k += BASE
        }
        return k + (BASE - T_MIN + 1) * d / (d + SKEW)
    }
}
