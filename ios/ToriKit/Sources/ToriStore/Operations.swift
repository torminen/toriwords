import Foundation
import GRDB
import ToriCore

/// Where a Sense value came from (`*_src` columns, §4.2).
public enum SenseSource: String, Sendable { case user, wiktionary, mtApple = "mt_apple", mtMLKit = "mt_mlkit" }

public struct NewSense: Hashable, Sendable {
    public var translation: String?
    public var definition: String?
    public var partOfSpeech: String?
    public var source: SenseSource
    public var dictVersion: String?
    public var dictHeadwordKey: String?
    public var dictSenseOrdinal: Int?

    public init(translation: String?, definition: String? = nil, partOfSpeech: String? = nil, source: SenseSource = .user,
                dictVersion: String? = nil, dictHeadwordKey: String? = nil, dictSenseOrdinal: Int? = nil) {
        self.translation = translation
        self.definition = definition
        self.partOfSpeech = partOfSpeech
        self.source = source
        self.dictVersion = dictVersion
        self.dictHeadwordKey = dictHeadwordKey
        self.dictSenseOrdinal = dictSenseOrdinal
    }

    var fields: [String: WireValue] {
        let src = WireValue.string(source.rawValue)
        return [
            "translation": translation.wire, "definition": definition.wire, "part_of_speech": partOfSpeech.wire,
            "translation_src": translation == nil ? .null : src, "definition_src": definition == nil ? .null : src,
            "pos_src": partOfSpeech == nil ? .null : src, "dict_version": dictVersion.wire,
            "dict_headword_key": dictHeadwordKey.wire, "dict_sense_ordinal": dictSenseOrdinal.map { .int(Int64($0)) } ?? .null,
        ]
    }
}

public enum EntryStatus: String, Sendable { case active, known, paused }

public enum KeyEditResult: Equatable, Sendable {
    case saved
    /// The new text collides with this live record; nothing was written (call again with `mergeIfDuplicate`).
    case duplicate(of: ToriID)
}

extension Optional where Wrapped == String {
    var wire: WireValue { map(WireValue.string) ?? .null }
}

extension ToriID {
    var wire: WireValue { .string(description) }
}

/// Local writes (repositories). Each call is one transaction: clocks, outbox, derived columns, merge, Cards, replay.
extension ToriStore {
    // MARK: Entry

    /// Edits the text. A match-key collision is a user-initiated merge (§11.7): returns `.duplicate` unless confirmed.
    public func setEntryText(_ id: ToriID, _ text: String, mergeIfDuplicate: Bool = false) throws -> KeyEditResult {
        try write { tx in
            let pair = try ToriID.fetchOne(tx.db, sql: "SELECT language_pair_id FROM entry WHERE id = ?", arguments: [id])
            if let other = try ToriID.fetchOne(tx.db, sql: """
                SELECT id FROM entry WHERE \(DuplicateMerge.live) AND language_pair_id IS ? AND match_key = ? AND id <> ? ORDER BY id LIMIT 1
                """, arguments: [pair, TextKey.matchKey(text), id]), !mergeIfDuplicate {
                return .duplicate(of: other)
            }
            try tx.set(.entry, id, ["text": .string(text), "updated_at": .int(tx.now)], rank: .user)
            return .saved
        }
    }

    public func setEntryNote(_ id: ToriID, _ note: String?) throws {
        try write { tx in try tx.set(.entry, id, ["note": note.wire, "updated_at": .int(tx.now)], rank: .user) }
    }

    public func setEntryIPA(_ id: ToriID, _ ipa: String?, rank: AuthorRank = .user) throws {
        try write { tx in try tx.set(.entry, id, ["ipa": ipa.wire], rank: rank) }
    }

    /// Exclude (Known / Pause) or resume; bulk in one transaction.
    public func setStatus(_ ids: [ToriID], _ status: EntryStatus) throws {
        try write { tx in
            for id in ids {
                try tx.set(.entry, id, ["status": .string(status == .active ? "active" : "excluded"),
                                        "excluded_reason": status == .active ? .null : .string(status.rawValue)], rank: .user)
            }
        }
    }

    /// Writes the tombstones (after the Undo window); bulk in one transaction.
    public func deleteEntries(_ ids: [ToriID]) throws {
        try write { tx in for id in ids { try tx.delete(.entry, id) } }
    }

    /// Opening the Entry screen: `needs_check = 0`, rank 0, only if it is 1 (§6.4).
    public func markChecked(_ id: ToriID) throws {
        try write(Self.clearNeedsCheck(id))
    }

    static func clearNeedsCheck(_ id: ToriID) -> (Tx) throws -> Void {
        { tx in
            if try Bool.fetchOne(tx.db, sql: "SELECT needs_check = 1 FROM entry WHERE id = ?", arguments: [id]) == true {
                try tx.set(.entry, id, ["needs_check": .bool(false)], rank: .automatic)
            }
        }
    }

    // MARK: Sense

    @discardableResult
    public func addSense(to entry: ToriID, _ sense: NewSense) throws -> ToriID {
        try write { tx in try Self.addSense(tx, entry: entry, sense, id: tx.newID(), rank: .user) }
    }

    static func addSense(_ tx: Tx, entry: ToriID, _ sense: NewSense, id: ToriID, rank: AuthorRank) throws -> ToriID {
        let last = try Double.fetchOne(tx.db, sql: "SELECT MAX(position) FROM sense WHERE canonical_entry_id = ? OR entry_id = ?",
                                       arguments: [entry, entry]) ?? 0
        var fields = sense.fields
        fields["entry_id"] = entry.wire
        fields["position"] = .double(last + 1)
        try tx.set(.sense, id, fields, rank: rank)
        if sense.translation?.isEmpty == false {
            try tx.set(.entry, entry, ["enrichment_status": .string("done")], rank: .automatic)
        }
        return id
    }

    /// User edit of a meaning; the edited fields become provenance `user`.
    public func editSense(_ id: ToriID, translation: String?, definition: String?, partOfSpeech: String?) throws {
        try write { tx in
            try tx.set(.sense, id, [
                "translation": translation.wire, "definition": definition.wire, "part_of_speech": partOfSpeech.wire,
                "translation_src": .string("user"), "definition_src": .string("user"), "pos_src": .string("user"),
            ], rank: .user)
        }
    }

    /// Reorder: a new fractional `position` (rank 1).
    public func moveSense(_ id: ToriID, to position: Double) throws {
        try write { tx in try tx.set(.sense, id, ["position": .double(position)], rank: .user) }
    }

    public func deleteSense(_ id: ToriID) throws {
        try write { tx in try tx.delete(.sense, id) }
    }

    // MARK: Context

    @discardableResult
    public func addContext(to entry: ToriID, sentence: String?, highlight: Capture.Highlight?, source: SourceInput?,
                           capturedAt: Int64) throws -> ToriID {
        try write { tx in
            let sourceID = try source.map { try Self.source(tx, $0) }
            return try Self.addContext(tx, entry: entry, sentence: sentence, highlight: highlight, sourceID: sourceID,
                                       capturedAt: capturedAt) ?? entry
        }
    }

    public func deleteContext(_ id: ToriID) throws {
        try write { tx in try tx.delete(.context, id) }
    }

    /// Adds a Context unless one with the same sentence key and canonical Source exists on the Entry.
    static func addContext(_ tx: Tx, entry: ToriID, sentence: String?, highlight: Capture.Highlight?, sourceID: ToriID?,
                           capturedAt: Int64) throws -> ToriID? {
        guard sentence != nil || sourceID != nil else { return nil }
        let key = TextKey.sentenceKey(sentence ?? "")
        let canonicalSource = try sourceID.map { try ToriID.fetchOne(tx.db, sql: "SELECT canonical_id FROM source WHERE id = ?", arguments: [$0]) ?? $0 }
        let existing = try Row.fetchAll(tx.db, sql: """
            SELECT c.id, c.sentence, s.canonical_id AS source FROM context c LEFT JOIN source s ON s.id = c.source_id
            WHERE c.deleted = 0 AND c.merged_into IS NULL AND (c.canonical_entry_id = ? OR c.entry_id = ?)
            """, arguments: [entry, entry])
        if let dup = existing.first(where: { TextKey.sentenceKey($0["sentence"] ?? "") == key && $0["source"] as ToriID? == canonicalSource }) {
            return dup["id"]
        }
        let id = tx.newID()
        try tx.set(.context, id, [
            "entry_id": entry.wire, "sentence": sentence.wire, "source_id": sourceID?.wire ?? .null,
            "highlight_offset": highlight.map { .int(Int64($0.offset)) } ?? .null,
            "highlight_length": highlight.map { .int(Int64($0.length)) } ?? .null, "captured_at": .int(capturedAt),
        ], rank: .user)
        return id
    }

    // MARK: Source

    /// Reuses a live Source by URL (deterministic ID) or by kind + title key + app (§11.7), else creates one.
    static func source(_ tx: Tx, _ input: SourceInput) throws -> ToriID {
        if let url = input.url, !url.isEmpty {
            let id = ToriID.source(urlKey: TextKey.urlKey(url))
            if try RecordIO.load(tx.db, .source, id) == nil {
                try tx.set(.source, id, ["kind": .string(input.kind.rawValue), "url": .string(url), "title": input.title.wire,
                                         "app": input.app.wire], rank: .user)
            }
            return try ToriID.fetchOne(tx.db, sql: "SELECT canonical_id FROM source WHERE id = ?", arguments: [id]) ?? id
        }
        let key = SourceKey(title: input.title, app: input.app, isSuggested: input.kind == .suggested)
        let rows = try Row.fetchAll(tx.db, sql: "SELECT id, kind, title, app FROM source WHERE \(DuplicateMerge.live) AND url IS NULL ORDER BY id")
        if let row = rows.first(where: { SourceKey(title: $0["title"], app: $0["app"], isSuggested: $0["kind"] == "suggested") == key }) {
            return row["id"]
        }
        let id = tx.newID()
        try tx.set(.source, id, ["kind": .string(input.kind.rawValue), "url": .null, "title": input.title.wire,
                                 "app": input.app.wire], rank: .user)
        return id
    }

    // MARK: Tags

    /// Tag Entries by name (reuse by tag key, else create): `present = 1` on the canonical pair's EntryTag (§11.7).
    public func tag(_ entries: [ToriID], name: String) throws {
        try write { tx in
            let tag = try Self.tagID(tx, name: name)
            for e in entries { try Self.setMembership(tx, entry: e, tag: tag, present: true) }
        }
    }

    /// Untag: `present = 0` on every EntryTag resolving to the pair.
    public func untag(_ entry: ToriID, tag: ToriID) throws {
        try write { tx in try Self.setMembership(tx, entry: entry, tag: tag, present: false) }
    }

    /// Rename; a collision with another live Tag's key returns `.duplicate` unless the merge is confirmed.
    public func renameTag(_ id: ToriID, to name: String, mergeIfDuplicate: Bool = false) throws -> KeyEditResult {
        try write { tx in
            if let other = try ToriID.fetchOne(tx.db, sql: "SELECT id FROM tag WHERE \(DuplicateMerge.live) AND name_key = ? AND id <> ? ORDER BY id LIMIT 1",
                                               arguments: [TextKey.tagKey(name), id]), !mergeIfDuplicate {
                return .duplicate(of: other)
            }
            try tx.set(.tag, id, ["name": .string(name)], rank: .user)
            return .saved
        }
    }

    public func deleteTag(_ id: ToriID) throws {
        try write { tx in try tx.delete(.tag, id) }
    }

    static func tagID(_ tx: Tx, name: String) throws -> ToriID {
        if let id = try ToriID.fetchOne(tx.db, sql: "SELECT id FROM tag WHERE \(DuplicateMerge.live) AND name_key = ? ORDER BY id LIMIT 1",
                                        arguments: [TextKey.tagKey(name)]) {
            return id
        }
        let id = tx.newID()
        try tx.set(.tag, id, ["name": .string(name)], rank: .user)
        return id
    }

    static func setMembership(_ tx: Tx, entry: ToriID, tag: ToriID, present: Bool) throws {
        let e = try ToriID.fetchOne(tx.db, sql: "SELECT canonical_id FROM entry WHERE id = ?", arguments: [entry]) ?? entry
        let t = try ToriID.fetchOne(tx.db, sql: "SELECT canonical_id FROM tag WHERE id = ?", arguments: [tag]) ?? tag
        if present {
            try tx.set(.entryTag, .entryTag(entry: e, tag: t), ["entry_id": e.wire, "tag_id": t.wire, "present": .bool(true)], rank: .user)
        } else {
            for id in try ToriID.fetchAll(tx.db, sql: "SELECT id FROM entry_tag WHERE canonical_entry_id = ? AND canonical_tag_id = ?",
                                          arguments: [e, t]) {
                try tx.set(.entryTag, id, ["present": .bool(false)], rank: .user)
            }
        }
    }

    // MARK: Enrichment (§6.4)

    /// Automatic fill of a pending Entry: Sense `v5(autosense:entry:0)`, `needs_check = 1`, `done`; all rank 0.
    public func fillAutomaticSense(_ entry: ToriID, _ sense: NewSense) throws {
        try write { tx in
            _ = try Self.addSense(tx, entry: entry, sense, id: .autoSense(entry: entry, ordinal: 0), rank: .automatic)
            try tx.set(.entry, entry, ["needs_check": .bool(true), "enrichment_status": .string("done")], rank: .automatic)
        }
    }

    /// Counts an MT failure; the third makes the Entry `unavailable`.
    public func recordEnrichmentFailure(_ entry: ToriID) throws {
        try write { tx in
            try tx.db.execute(sql: "UPDATE entry SET enrich_attempts = enrich_attempts + 1 WHERE id = ?", arguments: [entry])
            if try Int.fetchOne(tx.db, sql: "SELECT enrich_attempts FROM entry WHERE id = ?", arguments: [entry]) ?? 0 >= 3 {
                try tx.set(.entry, entry, ["enrichment_status": .string("unavailable")], rank: .automatic)
            }
        }
    }

    /// "Try again" / a new enrichment source: back to `pending` with a fresh attempt count.
    public func retryEnrichment(_ entry: ToriID) throws {
        try write { tx in
            try tx.db.execute(sql: "UPDATE entry SET enrich_attempts = 0 WHERE id = ?", arguments: [entry])
            try tx.set(.entry, entry, ["enrichment_status": .string("pending")], rank: .automatic)
        }
    }

    // MARK: Settings

    public func setNewWordsPerDay(_ n: Int) throws {
        try write { tx in try tx.set(.settings, .settings, ["new_words_per_day": .int(Int64(min(max(n, Self.newWordsPerDayRange.lowerBound), Self.newWordsPerDayRange.upperBound)))], rank: .user) }
    }

    /// A new parameter set triggers a full replay rebuild (§7.6).
    public func setSchedulerParameters(_ p: FSRSParameters, paramsID: String) throws {
        try write { tx in
            try tx.set(.settings, .settings, ["fsrs_w": .array(p.w.map(WireValue.double)), "desired_retention": .double(p.desiredRetention),
                                              "params_id": .string(paramsID)], rank: .user)
        }
    }

    // MARK: Review

    /// Commits one answer (§7.8): ReviewLog + scheduler step + `needs_check` clear + outbox, one transaction.
    /// `card` is a canonical Card ID from the queue. The step is incremental when the log is the Card's newest.
    @discardableResult
    public func commitAnswer(card: ToriID, rating: Rating, reviewedAt: Int64, utcOffsetMin: Int, answerMs: Int?) throws -> ToriID {
        try write { tx in
            let db = tx.db
            guard let row = try Row.fetchOne(db, sql: """
                SELECT entry_id, canonical_entry_id, stability, difficulty, last_review_day, due_day, reps, lapses FROM card WHERE id = ?
                """, arguments: [card]) else { throw StoreError.notFound }
            let id = tx.newID()
            let device = try ToriID.fetchOne(db, sql: "SELECT id FROM device WHERE is_this_device = 1")
            let newest = try !Bool.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM review_log WHERE canonical_card_id = ? AND (reviewed_at > ? OR (reviewed_at = ? AND id > ?)))
                """, arguments: [card, reviewedAt, reviewedAt, id])!
            try tx.set(.reviewLog, id, [
                "card_id": card.wire, "owner_entry_id": (row["entry_id"] as ToriID).wire, "reviewed_at": .int(reviewedAt),
                "utc_offset_min": .int(Int64(utcOffsetMin)), "rating": .int(Int64(rating.rawValue)),
                "answer_ms": answerMs.map { .int(Int64(min($0, 600_000))) } ?? .null, "device_id": device?.wire ?? .null,
            ], rank: .user)
            if newest {
                var state: CardState?
                if let s: Double = row["stability"] {
                    let last = try Int.fetchOne(db, sql: """
                        SELECT rating FROM review_log WHERE canonical_card_id = ? AND rating IS NOT NULL AND id <> ?
                        ORDER BY reviewed_at DESC, id DESC LIMIT 1
                        """, arguments: [card, id]).flatMap(Rating.init(rawValue:)) ?? .remembered
                    state = CardState(stability: s, difficulty: row["difficulty"], lastReviewDay: row["last_review_day"],
                                      dueDay: row["due_day"], reps: row["reps"], lapses: row["lapses"], lastRating: last, interval: nil)
                }
                let (p, paramsID) = try Replay.parameters(db)
                let day = DayModel.dayNumber(unixMs: reviewedAt, utcOffsetMin: utcOffsetMin)
                try Replay.writeCache(db, card, FSRS.step(state, cardID: card, day: day, rating: rating, p), paramsID)
                tx.stepped.insert(card)
            }
            if let entry: ToriID = row["canonical_entry_id"] { try Self.clearNeedsCheck(entry)(tx) }
            return id
        }
    }
}

public enum StoreError: Error, Equatable {
    case notFound
    case notABackup
    case updateRequired
}

/// Where a capture came from.
public struct SourceInput: Hashable, Sendable {
    public enum Kind: String, Sendable { case web, app, other, suggested }
    public var kind: Kind
    public var url: String?
    public var title: String?
    public var app: String?

    public init(kind: Kind, url: String? = nil, title: String? = nil, app: String? = nil) {
        self.kind = kind
        self.url = url
        self.title = title
        self.app = app
    }
}
