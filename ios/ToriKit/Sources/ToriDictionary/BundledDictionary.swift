import Foundation
import GRDB
import ToriCore

/// Read-only access to `dictionary.sqlite`: autocomplete, lookup, forms, reverse RU → EN lookup, related words, `meta`.
/// All text orders are SQL `BINARY` on UTF-8; row IDs are runtime-only, never stored in user data.
public final class BundledDictionary: Sendable {
    /// `meta.dictionary_version`, e.g. `2026.11.1` (`…-sample` for the Debug sample).
    public let version: String
    /// `meta.licence_text`: attribution shown in Settings → About.
    public let licenceText: String
    private let db: DatabaseQueue

    /// Opens the file read-only and immutable (`file:…?immutable=1`), as both the app and the extension do.
    public init(path: String) throws {
        var config = Configuration()
        config.readonly = true
        db = try DatabaseQueue(path: "file:\(path)?immutable=1", configuration: config)
        let meta = try db.read { try Self.meta($0) }
        guard let version = meta["dictionary_version"] else { throw DictionaryError.missingVersion(path) }
        self.version = version
        licenceText = meta["licence_text"] ?? ""
    }

    /// The bundled `dictionary.sqlite` (else the Debug sample), read in place: no copy, the bundle is read-only and the
    /// file is opened `immutable=1`. From an extension (`….app/PlugIns/X.appex`) it is the containing app's bundle.
    public static func bundledURL(bundle: URL = Bundle.main.bundleURL) -> URL? {
        let app = bundle.pathExtension == "appex" ? bundle.deletingLastPathComponent().deletingLastPathComponent() : bundle
        return ["dictionary.sqlite", "dictionary-sample.sqlite"].map { app.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The whole `meta` table (dump dates, hashes, build hash, versions).
    public func meta() throws -> [String: String] { try db.read { try Self.meta($0) } }

    static func meta(_ db: Database) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT key, value FROM meta").map { ($0["key"], $0["value"]) })
    }

    // MARK: Autocomplete

    /// Prefix range scan on `headword.key` (`key` = `TextKey.matchKey` of the input), phrases included, in dictionary
    /// order (`freq_rank` NULL last, `key`, `id`). `excluding` skips keys already shown from the user's vocabulary.
    public func autocomplete(prefix key: String, excluding: Set<String> = [], limit: Int = 8) throws -> [Completion] {
        guard !key.isEmpty, limit > 0 else { return [] }
        let skip = excluding.isEmpty ? "" : "AND h.key NOT IN \(Self.placeholders(excluding.count))"
        return try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT \(Self.summaryColumns) FROM headword h
                WHERE h.key >= ? AND h.key < ? || x'FFFF' \(skip)
                ORDER BY h.freq_rank IS NULL, h.freq_rank, h.key, h.id LIMIT ?
                """, arguments: StatementArguments([key, key] + excluding.sorted() + [limit])).map(Completion.init)
        }
    }

    static let summaryColumns = """
        h.id, h.text, h.key, h.pos, h.freq_rank, h.is_phrase,
        (SELECT t.text FROM translation_ru t WHERE t.headword_id = h.id ORDER BY t.rank LIMIT 1) AS primary_ru
        """

    // MARK: Lookup

    /// Exact `headword.key = key` hits (several POS possible) with senses and RU variants, in dictionary order.
    public func headwords(key: String) throws -> [Headword] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, text, key, pos, freq_rank, ipa, is_phrase FROM headword WHERE key = ?
                ORDER BY freq_rank IS NULL, freq_rank, key, id
                """, arguments: [key])
            return try rows.map { try Self.headword($0, db) }
        }
    }

    static func headword(_ r: Row, _ db: Database) throws -> Headword {
        let id: Int64 = r["id"]
        let senses = try Row.fetchAll(db, sql: """
            SELECT s.id, s.ordinal, s.gloss_en, s.tags,
              (SELECT group_concat(text_en, char(31)) FROM (SELECT text_en FROM example WHERE sense_id = s.id ORDER BY rowid)) AS ex
            FROM sense s WHERE s.headword_id = ? ORDER BY s.ordinal
            """, arguments: [id])
        let ordinalOf = Dictionary(uniqueKeysWithValues: senses.map { ($0["id"] as Int64, $0["ordinal"] as Int) })
        let translations = try Row.fetchAll(db, sql: """
            SELECT text, sense_id, origin, rank FROM translation_ru WHERE headword_id = ? ORDER BY rank
            """, arguments: [id]).map { t in
            Translation(text: t["text"], senseOrdinal: (t["sense_id"] as Int64?).flatMap { ordinalOf[$0] },
                        origin: Translation.Origin(rawValue: t["origin"]) ?? .enwikt, rank: t["rank"])
        }
        return Headword(
            id: id, text: r["text"], key: r["key"], partOfSpeech: r["pos"], freqRank: r["freq_rank"], ipa: r["ipa"],
            isPhrase: r["is_phrase"],
            senses: senses.map { s in
                Sense(ordinal: s["ordinal"], glossEn: s["gloss_en"], tags: s["tags"],
                      examples: ((s["ex"] as String?) ?? "").split(separator: "\u{1F}").map(String.init))
            },
            translations: translations)
    }

    /// Base forms whose inflection/alternative has this key (`form.form_key`), in dictionary order.
    public func baseForms(of key: String) throws -> [BaseForm] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT \(Self.summaryColumns), f.form_tags FROM form f JOIN headword h ON h.id = f.headword_id
                WHERE f.form_key = ? ORDER BY h.freq_rank IS NULL, h.freq_rank, h.key, h.id
                """, arguments: [key]).map { BaseForm(headword: Completion($0), formTags: $0["form_tags"]) }
        }
    }

    /// Lookup for a typed or captured text: exact hit; else the base-form offer (P1, never for phrases);
    /// and dictionary phrases contained in a longer text (`took off` in a sentence → `take off`).
    public func resolve(_ text: String) throws -> Resolution {
        let key = TextKey.matchKey(text)
        guard !key.isEmpty else { return Resolution(key: key, headwords: [], baseForms: [], containedPhrases: []) }
        let headwords = try headwords(key: key)
        let isPhrase = key.unicodeScalars.contains(" ")
        let bases = headwords.isEmpty && !isPhrase ? try baseForms(of: key) : []
        return Resolution(key: key, headwords: headwords, baseForms: bases,
                          containedPhrases: isPhrase ? try containedPhrases(in: text) : [])
    }

    /// Dictionary phrases (2–6 words) found in the text, also through base forms of its words; the text's own key is
    /// excluded. Ordered by first position in the text, then longer first.
    public func containedPhrases(in text: String, limit: Int = 8) throws -> [Completion] {
        let tokens = Array(TextKey.matchKey(text).split(separator: " ").map { TextKey.matchKey(String($0)) }
            .filter { !$0.isEmpty }.prefix(Self.maxTokens))
        guard tokens.count >= 2 else { return [] }
        let whole = tokens.joined(separator: " ")
        return try db.read { db in
            var options: [String: [String]] = [:]
            let unique = Array(Set(tokens))
            for r in try Row.fetchAll(db, sql: """
                SELECT DISTINCT f.form_key, h.key FROM form f JOIN headword h ON h.id = f.headword_id
                WHERE f.form_key IN \(Self.placeholders(unique.count)) AND h.is_phrase = 0 ORDER BY f.form_key, h.key
                """, arguments: StatementArguments(unique)) {
                options[r["form_key"], default: []].append(r["key"])
            }
            var candidates: [(key: String, start: Int, length: Int)] = []
            var seen = Set<String>()
            for start in tokens.indices {
                for length in stride(from: min(Self.maxPhraseWords, tokens.count - start), through: 2, by: -1) {
                    for key in Self.variants(Array(tokens[start..<start + length]), options) where key != whole {
                        if seen.insert(key).inserted { candidates.append((key, start, length)) }
                    }
                }
            }
            guard !candidates.isEmpty else { return [] }
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(Self.summaryColumns) FROM headword h
                WHERE h.is_phrase = 1 AND h.key IN \(Self.placeholders(candidates.count))
                ORDER BY h.freq_rank IS NULL, h.freq_rank, h.key, h.id
                """, arguments: StatementArguments(candidates.map(\.key)))
            var byKey: [String: Completion] = [:]
            for r in rows where byKey[r["key"]] == nil { byKey[r["key"]] = Completion(r) }
            return Array(candidates.compactMap { byKey[$0.key] }.prefix(limit))
        }
    }

    static func placeholders(_ n: Int) -> String { "(" + Array(repeating: "?", count: max(n, 1)).joined(separator: ",") + ")" }

    static let maxTokens = 64
    static let maxPhraseWords = 6
    static let maxVariants = 16

    /// The words as typed, then with words replaced by their base forms (bounded).
    static func variants(_ words: [String], _ options: [String: [String]]) -> [String] {
        var out: [[String]] = [[]]
        for w in words {
            let choices = [w] + (options[w] ?? []).filter { $0 != w }
            out = Array(out.flatMap { prefix in choices.map { prefix + [$0] } }.prefix(maxVariants))
        }
        return out.map { $0.joined(separator: " ") }
    }

    // MARK: Reverse RU → EN

    /// For input with Cyrillic and no Latin letters: prefix match of the folded input on `ru_fts`; one row per headword,
    /// ordered by its best matching `translation_ru.rank`, then `freq_rank` (NULL last), `key`, `id`.
    public func reverse(_ input: String, limit: Int = 8) throws -> [ReverseHit] {
        guard Self.isRussianInput(input) else { return [] }
        let folded = TextKey.searchFold(input)
        let match = "\"" + folded.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
        return try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT h.id, h.text, h.key, h.pos, h.freq_rank, h.is_phrase, t.text AS primary_ru, MIN(t.rank) AS best
                FROM ru_fts JOIN translation_ru t ON t.id = ru_fts.rowid JOIN headword h ON h.id = t.headword_id
                WHERE ru_fts MATCH ? GROUP BY h.id
                ORDER BY best, h.freq_rank IS NULL, h.freq_rank, h.key, h.id LIMIT ?
                """, arguments: [match, limit]).map { ReverseHit(headword: Completion($0), matchedTranslation: $0["primary_ru"]) }
        }
    }

    /// Has a Cyrillic letter (U+0400–U+04FF) and no Latin letter (fixture README list).
    public static func isRussianInput(_ text: String) -> Bool {
        var cyrillic = false
        for c in text.unicodeScalars {
            if Capture.isLatinLetter(c) { return false }
            if (0x400...0x4FF).contains(c.value) && c.properties.isAlphabetic { cyrillic = true }
        }
        return cyrillic
    }

    // MARK: Related words

    /// Up to `limit` related headwords: kind (`synonym`, `related`, `derived`, `phrase`), then `freq_rank` NULL last,
    /// then `related_headword_id`. Empty when the build pruned `related`.
    public func related(to headwordID: Int64, limit: Int = 8) throws -> [RelatedWord] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT \(Self.summaryColumns), r.kind FROM related r JOIN headword h ON h.id = r.related_headword_id
                WHERE r.headword_id = ?
                ORDER BY CASE r.kind WHEN 'synonym' THEN 0 WHEN 'related' THEN 1 WHEN 'derived' THEN 2 ELSE 3 END,
                  h.freq_rank IS NULL, h.freq_rank, r.related_headword_id
                LIMIT ?
                """, arguments: [headwordID, limit]).map {
                RelatedWord(headword: Completion($0), kind: RelatedWord.Kind(rawValue: $0["kind"]) ?? .related)
            }
        }
    }
}

public enum DictionaryError: Error, Equatable {
    case missingVersion(String)
}

/// One headword row as shown in lists (autocomplete, base forms, phrases, reverse, related).
public struct Completion: Hashable, Sendable {
    public var id: Int64
    public var text: String
    public var key: String
    public var partOfSpeech: String
    public var freqRank: Int?
    public var isPhrase: Bool
    /// The rank-1 RU variant, nil when the headword has none.
    public var primaryTranslation: String?

    init(_ r: Row) {
        id = r["id"]
        text = r["text"]
        key = r["key"]
        partOfSpeech = r["pos"]
        freqRank = r["freq_rank"]
        isPhrase = r["is_phrase"]
        primaryTranslation = r["primary_ru"]
    }
}

public struct Headword: Hashable, Sendable {
    public var id: Int64
    public var text: String
    public var key: String
    public var partOfSpeech: String
    public var freqRank: Int?
    public var ipa: String?
    public var isPhrase: Bool
    /// By `ordinal`.
    public var senses: [Sense]
    /// All RU variants of the headword by `rank`; `senseOrdinal` nil = not tied to a sense.
    public var translations: [Translation]
}

public struct Sense: Hashable, Sendable {
    public var ordinal: Int
    public var glossEn: String
    public var tags: String?
    public var examples: [String]
}

public struct Translation: Hashable, Sendable {
    public enum Origin: String, Sendable { case enwikt, ruwikt }
    public var text: String
    public var senseOrdinal: Int?
    public var origin: Origin
    public var rank: Int
}

public struct BaseForm: Hashable, Sendable {
    public var headword: Completion
    /// e.g. `past`, `plural`, `alternative`.
    public var formTags: String?
}

public struct ReverseHit: Hashable, Sendable {
    public var headword: Completion
    /// The best-ranked RU variant that matched the query.
    public var matchedTranslation: String
}

public struct RelatedWord: Hashable, Sendable {
    public enum Kind: String, Sendable { case synonym, related, derived, phrase }
    public var headword: Completion
    public var kind: Kind
}

public struct Resolution: Hashable, Sendable {
    public var key: String
    /// Exact hits; empty = no dictionary entry for the key.
    public var headwords: [Headword]
    /// "Did you mean *run*?" — only when there is no exact hit and the input is a single word.
    public var baseForms: [BaseForm]
    /// Dictionary phrases inside a longer input.
    public var containedPhrases: [Completion]
}
