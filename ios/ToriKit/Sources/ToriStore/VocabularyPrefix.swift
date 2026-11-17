import GRDB
import ToriCore

/// A live canonical Entry whose `match_key` starts with the typed key (Add-screen autocomplete, §6.2 step 1a).
public struct VocabularyHit: Hashable, Sendable {
    public var id: ToriID
    public var text: String
    public var matchKey: String
}

extension StoreReader {
    /// Prefix range scan on the `(language_pair_id, match_key)` index, `BINARY` order (§4.1 Text order), then `id`.
    public func vocabularyPrefix(_ key: String, limit: Int = 3,
                                 pair: ToriID = ToriID.languagePair(native: "ru", target: "en")) throws -> [VocabularyHit] {
        guard !key.isEmpty, limit > 0 else { return [] }
        return try Row.fetchAll(db, sql: """
            SELECT e.id, e.text, e.match_key FROM entry e
            WHERE e.language_pair_id = ? AND e.match_key >= ? AND e.match_key < ? || x'FFFF' AND \(Self.liveEntry)
            ORDER BY e.match_key, e.id LIMIT ?
            """, arguments: [pair, key, key, limit]).map {
            VocabularyHit(id: $0["id"], text: $0["text"], matchKey: $0["match_key"])
        }
    }
}
