package com.toriwords.core

import java.text.Normalizer

/**
 * Text keys. Character sets are the explicit lists in `fixtures/README.md`, never a Unicode property lookup or a
 * locale-dependent call, so all platforms agree. Everything iterates by code point, never by UTF-16 `Char`.
 */
object TextKey {
    /** Key for duplicate detection of Entry texts and dictionary lookups. */
    fun matchKey(text: String): String {
        val s = collapse(codePoints(lowercase(foldSteps1to3(text))))
        var from = 0
        var to = s.size
        while (from < to && (isPunctuation(s[from]) || isWhitespace(s[from]))) from++
        while (to > from && (isPunctuation(s[to - 1]) || isWhitespace(s[to - 1]))) to--
        return yo(string(s.subList(from, to)))
    }

    /** Key for duplicate translations within an Entry (same rules as [matchKey]). */
    fun translationKey(text: String): String = matchKey(text)

    /** Key for duplicate Context sentences: case is kept. */
    fun sentenceKey(text: String): String = yo(collapse(foldSteps1to3(text)))

    /** Key for Tag names: NFC, lowercase, collapse, ё → е (no quote mapping, no ignorable removal). */
    fun tagKey(text: String): String = yo(collapse(lowercase(nfc(text))))

    /** Search fold for the Words list search (no edge stripping). */
    fun searchFold(text: String): String = yo(collapse(lowercase(foldSteps1to3(text))))

    /** An Entry text is a phrase when its match key contains whitespace. */
    fun isPhrase(text: String): Boolean = matchKey(text).contains(' ')

    // Explicit character lists

    private val singleQuotes = setOf(0x2019, 0x2018, 0x02BC, 0x2032)
    private val doubleQuotes = setOf(0x201C, 0x201D, 0x201E, 0x2033)
    private val dashes = setOf(0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2212)

    /** Space separators (Zs) other than U+0020. */
    private val spaceSeparators = setOf(0x00A0, 0x1680, 0x202F, 0x205F, 0x3000) + (0x2000..0x200A)

    /** Removed outright: soft hyphen, ZWSP, ZWNJ, ZWJ, word joiner, BOM. */
    private val defaultIgnorables = setOf(0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF)

    /** Whitespace for collapse, trim and tokens. */
    private val whitespace = setOf(0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0x2028, 0x2029)

    private val punctuationTypes = setOf(
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION,
    ).map { it.toInt() }.toSet()

    internal fun isWhitespace(c: Int): Boolean = c in whitespace

    internal fun isPunctuation(c: Int): Boolean = Character.getType(c) in punctuationTypes

    // Steps

    internal fun nfc(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFC)

    /** NFC, quote/dash/space mapping, default-ignorable removal. */
    private fun foldSteps1to3(s: String): String {
        val out = StringBuilder()
        for (c in codePoints(nfc(s))) {
            when (c) {
                in defaultIgnorables -> {}
                in singleQuotes -> out.append('\'')
                in doubleQuotes -> out.append('"')
                in dashes -> out.append('-')
                in spaceSeparators -> out.append(' ')
                else -> out.appendCodePoint(c)
            }
        }
        return out.toString()
    }

    /**
     * Full default lowercase mapping per code point: no locale, no context (Σ → σ, never ς; İ → i̇). A lone code point
     * has no casing context, so `String.lowercase()` (root locale) gives exactly the unconditional mapping.
     */
    internal fun lowercase(s: String): String {
        val out = StringBuilder()
        for (c in codePoints(s)) out.append(String(Character.toChars(c)).lowercase())
        return out.toString()
    }

    /** Runs of whitespace → one U+0020; leading and trailing whitespace removed. */
    private fun collapse(s: String): String = string(collapse(codePoints(s)))

    private fun collapse(s: List<Int>): List<Int> {
        val out = ArrayList<Int>(s.size)
        var pending = false
        for (c in s) {
            if (isWhitespace(c)) {
                pending = true
            } else {
                if (pending && out.isNotEmpty()) out.add(' '.code)
                pending = false
                out.add(c)
            }
        }
        return out
    }

    private fun yo(s: String): String = s.replace('ё', 'е').replace('Ё', 'Е')

    internal fun codePoints(s: String): List<Int> = s.codePoints().toArray().asList()

    internal fun string(codePoints: List<Int>): String {
        val out = StringBuilder()
        for (c in codePoints) out.appendCodePoint(c)
        return out.toString()
    }
}

/** Natural key of a Source without URL. */
data class SourceKey(val title: String, val app: String?, val suggested: Boolean) {
    companion object {
        fun of(title: String?, app: String?, isSuggested: Boolean): SourceKey =
            SourceKey(TextKey.matchKey(title ?: ""), app, isSuggested)
    }
}
