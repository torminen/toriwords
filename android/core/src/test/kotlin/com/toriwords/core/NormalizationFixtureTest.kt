package com.toriwords.core

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource

class NormalizationFixtureTest {
    companion object {
        @JvmStatic fun textKey() = Fixtures.cases(
            *listOf("match-key", "translation-key", "sentence-key", "tag-key", "search-fold", "url-key")
                .map { "normalization/$it.json" }.toTypedArray(),
        )
        @JvmStatic fun sourceKey() = Fixtures.cases("normalization/source-key.json")
        @JvmStatic fun textOrder() = Fixtures.cases("normalization/text-order.json")

        /** BINARY collation on UTF-8 = unsigned byte order. */
        val utf8Order = Comparator<ByteArray> { a, b -> java.util.Arrays.compareUnsigned(a, b) }
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun textKey(c: FixtureCase) {
        val fn: (String) -> String = when (val f = c.file.getValue("function").str) {
            "matchKey" -> TextKey::matchKey
            "translationKey" -> TextKey::translationKey
            "sentenceKey" -> TextKey::sentenceKey
            "tagKey" -> TextKey::tagKey
            "searchFold" -> TextKey::searchFold
            "urlKey" -> UrlKey::of
            else -> error("unknown function $f")
        }
        assertEquals(c["expected"].str, fn(c["input"].str!!))
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun sourceKey(c: FixtureCase) {
        val i = c["input"]
        val e = c["expected"]
        val key = SourceKey.of(i["title"].str, i["app"].str, i["kind"].str == "suggested")
        assertEquals(e["title"].str, key.title)
        assertEquals(e["app"].str, key.app)
        assertEquals(e["suggested"].bool, key.suggested)
    }

    /** In memory here, as on iOS; the SQL check comes with the store. */
    @ParameterizedTest(name = "{0}") @MethodSource
    fun textOrder(c: FixtureCase) {
        var keys = c["keys"].array.map { it.str!!.toByteArray(Charsets.UTF_8) }.sortedWith(utf8Order)
        c["prefix"].str?.let { p ->
            val lo = p.toByteArray(Charsets.UTF_8)
            val hi = lo + byteArrayOf(0xFF.toByte(), 0xFF.toByte())
            keys = keys.filter { utf8Order.compare(it, lo) >= 0 && utf8Order.compare(it, hi) < 0 }
        }
        assertEquals(c["expected"].array.map { it.str }, keys.map { String(it, Charsets.UTF_8) })
    }

    @Test
    fun isPhrase() {
        assertTrue(TextKey.isPhrase("give up"))
        assertTrue(TextKey.isPhrase("  give up "))
        assertFalse(TextKey.isPhrase(" run. "))
    }
}
