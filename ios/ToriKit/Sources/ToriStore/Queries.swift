import Foundation
import GRDB
import ToriCore
import ToriShared

/// Translation state shown in the UI (§6.4), first match wins.
public enum TranslationState: Hashable, Sendable {
    case has(String)
    case notFound, pending, none

    public var needsTranslation: Bool { if case .has = self { false } else { true } }
}

/// Entry-level stage marker (Words list, filters).
public enum WordStage: Hashable, Sendable {
    case needsTranslation, new, learning, knownWell, known, paused
}

public struct WordRow: Hashable, Sendable {
    public var id: ToriID
    public var text: String
    public var translation: TranslationState
    public var stage: WordStage
    public var isPhrase: Bool
    public var needsCheck: Bool
    public var createdAt: Int64
    public var nextDueDay: Int?
}

public struct WordsQuery: Hashable, Sendable {
    public enum Filter: Hashable, Sendable {
        case all, needsTranslation, checkTranslation, phrases
        case stage(WordStage)
    }

    public enum Sort: Hashable, Sendable { case newest, alphabetical, nextDue }

    public var filter: Filter
    /// Any-of; IDs of live Tags.
    public var tags: Set<ToriID>
    public var source: ToriID?
    public var search: String
    public var sort: Sort

    public init(filter: Filter = .all, tags: Set<ToriID> = [], source: ToriID? = nil, search: String = "", sort: Sort = .newest) {
        self.filter = filter
        self.tags = tags
        self.source = source
        self.search = search
        self.sort = sort
    }
}

public struct EntryDetail: Hashable, Sendable {
    public struct Sense: Hashable, Sendable {
        public var id: ToriID
        public var translation: String?
        public var definition: String?
        public var partOfSpeech: String?
        /// The user edited the translation (rank 1).
        public var translationByUser: Bool
        /// Provenance of the translation (`wiktionary` shows the Wiktionary mark).
        public var translationSource: SenseSource?
    }

    public struct Context: Hashable, Sendable {
        public var id: ToriID
        public var sentence: String?
        public var highlight: Capture.Highlight?
        public var sourceID: ToriID?
        public var sourceTitle: String?
        public var sourceURL: String?
        public var capturedAt: Int64
    }

    public struct Card: Hashable, Sendable {
        public var id: ToriID
        public var direction: CardDirection
        public var stage: CardStage
        public var dueDay: Int?
        public var reps: Int
    }

    public var id: ToriID
    public var text: String
    public var ipa: String?
    public var note: String?
    public var status: EntryStatus
    public var needsCheck: Bool
    public var translation: TranslationState
    public var stage: WordStage
    public var createdAt: Int64
    public var senses: [Sense]
    public var contexts: [Context]
    public var tags: [TagRow]
    public var cards: [Card]
}

public struct TagRow: Hashable, Sendable {
    public var id: ToriID
    public var name: String
}

public struct ProgressSummary: Hashable, Sendable {
    public var today: ProgressStats.Today
    public var vocabulary: ProgressStats.Vocabulary
    public var activity: [Int]
    public var capturedPerWeek: [Int]
    public var topSources: [ProgressStats.SourceUsage]
}

extension StoreReader {
    static let liveEntry = "e.deleted = 0 AND e.merged_into IS NULL"
    static let liveSense = "s.deleted = 0 AND s.merged_into IS NULL"
    /// First translation in display order: own Senses first, then `position`, then ID (§11.7).
    static let senseOrder = "(s.entry_id <> s.canonical_entry_id), s.position, s.id"

    // MARK: Queue, Home, widget

    /// Live canonical Entries with their live canonical Cards (only while reviewable) and the rated logs of those Cards.
    public func queueInput() throws -> (entries: [QueueEntry], logs: [ReviewLogInput]) {
        let rows = try Row.fetchAll(db, sql: """
            SELECT e.id AS entry, e.created_at, e.status, c.id AS card, c.direction FROM entry e
            LEFT JOIN card c ON c.canonical_entry_id = e.id AND c.id = c.canonical_card_id
              AND EXISTS (SELECT 1 FROM sense s WHERE s.canonical_entry_id = e.id AND \(Self.liveSense) AND s.translation <> '')
            WHERE \(Self.liveEntry) ORDER BY e.id
            """)
        var entries: [QueueEntry] = []
        for row in rows {
            let id: ToriID = row["entry"]
            if entries.last?.id != id {
                entries.append(QueueEntry(id: id, createdAt: row["created_at"] ?? 0, isActive: row["status"] == "active", cards: []))
            }
            if let card: ToriID = row["card"], let d = (row["direction"] as String?).flatMap(CardDirection.init(rawValue:)) {
                entries[entries.count - 1].cards.append(QueueCard(id: card, direction: d))
            }
        }
        let logs = try Row.fetchAll(db, sql: """
            SELECT l.id, l.canonical_card_id, l.reviewed_at, l.utc_offset_min, l.rating FROM review_log l
            JOIN card c ON c.id = l.canonical_card_id JOIN entry e ON e.id = c.canonical_entry_id
            WHERE \(Self.liveEntry) AND l.rating IS NOT NULL AND l.reviewed_at IS NOT NULL
            """).map { r in
            ReviewLogInput(id: r["id"], cardID: r["canonical_card_id"], reviewedAt: r["reviewed_at"],
                           utcOffsetMin: r["utc_offset_min"] ?? 0, rating: (r["rating"] as Int?).flatMap(Rating.init(rawValue:)))
        }
        return (entries, logs)
    }

    public func newWordsPerDay() throws -> Int {
        try Int.fetchOne(db, sql: "SELECT new_words_per_day FROM settings WHERE id = ?", arguments: [ToriID.settings]) ?? 10
    }

    /// Today's queue (§7.7): Home counts and the session list.
    public func dailyQueue(now: Int64, utcOffsetMin: Int, extensions: QueueExtensions = QueueExtensions()) throws -> DailyQueue {
        let (entries, logs) = try queueInput()
        return DailyQueue.build(entries: entries, logs: logs, today: DayModel.dayNumber(unixMs: now, utcOffsetMin: utcOffsetMin),
                                newWordsPerDay: try newWordsPerDay(), extensions: extensions, parameters: try Replay.parameters(db).0)
    }

    public func widgetSnapshot(now: Int64, utcOffsetMin: Int) throws -> WidgetSnapshot {
        let (entries, logs) = try queueInput()
        return WidgetSnapshot.compute(entries: entries, logs: logs, now: now, utcOffsetMin: utcOffsetMin,
                                      newWordsPerDay: try newWordsPerDay(), parameters: try Replay.parameters(db).0)
    }

    // MARK: Words list and search (§14.3)

    public func words(_ q: WordsQuery) throws -> [WordRow] {
        var conditions = [Self.liveEntry]
        var args: [DatabaseValueConvertible?] = []
        switch q.filter {
        case .needsTranslation: conditions.append("translation IS NULL")
        case .checkTranslation: conditions.append("e.needs_check = 1")
        case .phrases: conditions.append("instr(e.match_key, ' ') > 0")
        case .all, .stage: break
        }
        if !q.tags.isEmpty {
            conditions.append("""
                EXISTS (SELECT 1 FROM entry_tag et JOIN tag t ON t.id = et.canonical_tag_id
                WHERE et.canonical_entry_id = e.id AND et.present = 1 AND t.deleted = 0 AND t.merged_into IS NULL
                AND t.id IN \(Database.placeholders(q.tags.count)))
                """)
            args += q.tags.map { $0 as DatabaseValueConvertible? }
        }
        if let source = q.source {
            conditions.append("""
                EXISTS (SELECT 1 FROM context c JOIN source so ON so.id = c.source_id
                WHERE c.canonical_entry_id = e.id AND c.deleted = 0 AND c.merged_into IS NULL AND so.canonical_id = ?)
                """)
            args.append(source)
        }
        let fold = TextKey.searchFold(q.search)
        if !fold.isEmpty {
            conditions.append("""
                (e.text_fold LIKE ? ESCAPE '\\'
                OR EXISTS (SELECT 1 FROM sense s WHERE s.canonical_entry_id = e.id AND \(Self.liveSense)
                  AND (s.translation_fold LIKE ? ESCAPE '\\' OR s.definition_fold LIKE ? ESCAPE '\\'))
                OR EXISTS (SELECT 1 FROM context c WHERE c.canonical_entry_id = e.id AND c.deleted = 0 AND c.merged_into IS NULL
                  AND c.sentence_fold LIKE ? ESCAPE '\\'))
                """)
            args += Array(repeating: Self.likePattern(fold), count: 4)
        }
        let order = switch q.sort {
        case .newest: "e.created_at DESC, e.id"
        case .alphabetical: "e.match_key, e.id"
        // Only New Cards (no due day yet) after scheduled ones; no Cards / excluded last, by Newest.
        case .nextDue: "(e.status <> 'active' OR stages IS NULL), next_due IS NULL, next_due, e.created_at DESC, e.id"
        }
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM (\(Self.wordColumns)) e WHERE \(conditions.joined(separator: " AND ")) ORDER BY \(order)
            """, arguments: StatementArguments(args))
        var result = rows.map(Self.wordRow)
        if case .stage(let s) = q.filter { result = result.filter { $0.stage == s } }
        return result
    }

    /// One row per Entry with the columns `wordRow` reads.
    static let wordColumns = """
        SELECT e.id, e.text, e.text_fold, e.deleted, e.merged_into, e.status, e.excluded_reason, e.enrichment_status,
                e.needs_check, e.created_at, e.match_key,
                (SELECT s.translation FROM sense s WHERE s.canonical_entry_id = e.id AND \(Self.liveSense) AND s.translation <> ''
                 ORDER BY \(Self.senseOrder) LIMIT 1) AS translation,
                (SELECT MIN(c.due_day) FROM card c WHERE c.canonical_entry_id = e.id AND c.id = c.canonical_card_id) AS next_due,
                (SELECT group_concat(c.stage) FROM card c WHERE c.canonical_entry_id = e.id AND c.id = c.canonical_card_id) AS stages
              FROM entry e
        """

    /// Add autocomplete (a): live Entries whose match key starts with the typed key, by key then ID (§6.2 item 1).
    public func vocabularyMatches(prefix text: String, limit: Int = 3) throws -> [WordRow] {
        let key = TextKey.matchKey(text)
        guard !key.isEmpty else { return [] }
        return try Row.fetchAll(db, sql: """
            SELECT * FROM (\(Self.wordColumns)) e WHERE \(Self.liveEntry) AND substr(e.match_key, 1, length(?)) = ?
            ORDER BY e.match_key, e.id LIMIT ?
            """, arguments: [key, key, limit]).map(Self.wordRow)
    }

    /// The live Entry with exactly this match key ("Already in your vocabulary", §5.3).
    public func entryID(matching text: String) throws -> ToriID? {
        try ToriID.fetchOne(db, sql: "SELECT id FROM entry e WHERE \(Self.liveEntry) AND e.match_key = ? ORDER BY e.id LIMIT 1",
                            arguments: [TextKey.matchKey(text)])
    }

    /// Live Entries per live canonical Tag (Tags screen, tag filter counts).
    public func tagCounts() throws -> [ToriID: Int] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT et.canonical_tag_id AS tag, COUNT(DISTINCT e.id) AS n FROM entry_tag et JOIN entry e ON e.id = et.canonical_entry_id
            WHERE et.present = 1 AND \(Self.liveEntry) GROUP BY et.canonical_tag_id
            """)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0["tag"] as ToriID, $0["n"] as Int) })
    }

    static func likePattern(_ fold: String) -> String {
        "%" + fold.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }

    static func translationState(_ row: Row) -> TranslationState {
        if let t: String = row["translation"] { return .has(t) }
        switch row["enrichment_status"] as String? {
        case "unavailable": return .notFound
        case "pending": return .pending
        default: return .none
        }
    }

    static func stage(_ row: Row, translation: TranslationState) -> WordStage {
        if row["status"] == "excluded" { return row["excluded_reason"] == "paused" ? .paused : .known }
        if translation.needsTranslation { return .needsTranslation }
        let stages = ((row["stages"] as String?) ?? "").split(separator: ",").map(String.init)
        if stages.isEmpty || stages.allSatisfy({ $0 == "new" }) { return .new }
        return stages.allSatisfy { $0 == "known_well" } ? .knownWell : .learning
    }

    static func wordRow(_ row: Row) -> WordRow {
        let t = translationState(row)
        let text: String = row["text"] ?? ""
        return WordRow(id: row["id"], text: text, translation: t, stage: stage(row, translation: t), isPhrase: TextKey.isPhrase(text),
                       needsCheck: row["needs_check"] == 1, createdAt: row["created_at"] ?? 0, nextDueDay: row["next_due"])
    }

    // MARK: Entry detail

    /// The live canonical Entry (a merged or deleted ID resolves to its survivor; nil when deleted).
    public func entry(_ id: ToriID) throws -> EntryDetail? {
        guard let canonical = try ToriID.fetchOne(db, sql: "SELECT canonical_id FROM entry WHERE id = ?", arguments: [id]),
              let row = try Row.fetchOne(db, sql: """
                SELECT e.*, (SELECT s.translation FROM sense s WHERE s.canonical_entry_id = e.id AND \(Self.liveSense)
                  AND s.translation <> '' ORDER BY \(Self.senseOrder) LIMIT 1) AS translation,
                (SELECT group_concat(c.stage) FROM card c WHERE c.canonical_entry_id = e.id AND c.id = c.canonical_card_id) AS stages
                FROM entry e WHERE e.id = ? AND \(Self.liveEntry)
                """, arguments: [canonical]) else { return nil }
        let senses = try Row.fetchAll(db, sql: """
            SELECT s.* FROM sense s WHERE s.canonical_entry_id = ? AND \(Self.liveSense) ORDER BY \(Self.senseOrder)
            """, arguments: [canonical]).map { r in
            let clocks = JSONText.decode([String: FieldClock].self, r["field_clocks"]) ?? [:]
            return EntryDetail.Sense(id: r["id"], translation: r["translation"], definition: r["definition"],
                                     partOfSpeech: r["part_of_speech"], translationByUser: clocks["translation"]?.u == 1,
                                     translationSource: (r["translation_src"] as String?).flatMap(SenseSource.init(rawValue:)))
        }
        let contexts = try Row.fetchAll(db, sql: """
            SELECT c.id, c.sentence, c.highlight_offset, c.highlight_length, c.captured_at, so.id AS source_id, so.title, so.url
            FROM context c LEFT JOIN source s0 ON s0.id = c.source_id LEFT JOIN source so ON so.id = s0.canonical_id AND so.deleted = 0
            WHERE c.canonical_entry_id = ? AND c.deleted = 0 AND c.merged_into IS NULL ORDER BY c.captured_at, c.id
            """, arguments: [canonical]).map { r in
            let highlight: Capture.Highlight? = {
                guard let o: Int = r["highlight_offset"], let l: Int = r["highlight_length"] else { return nil }
                return Capture.Highlight(offset: o, length: l)
            }()
            return EntryDetail.Context(id: r["id"], sentence: r["sentence"], highlight: highlight, sourceID: r["source_id"],
                                       sourceTitle: r["title"], sourceURL: r["url"], capturedAt: r["captured_at"] ?? 0)
        }
        let cards = try Row.fetchAll(db, sql: """
            SELECT id, direction, stage, due_day, reps FROM card WHERE canonical_entry_id = ? AND id = canonical_card_id
            """, arguments: [canonical]).compactMap { r -> EntryDetail.Card? in
            guard let d = (r["direction"] as String?).flatMap(CardDirection.init(rawValue:)) else { return nil }
            return EntryDetail.Card(id: r["id"], direction: d, stage: (r["stage"] as String?).flatMap(CardStage.init(rawValue:)) ?? .new,
                                    dueDay: r["due_day"], reps: r["reps"] ?? 0)
        }.sorted { $0.direction < $1.direction }
        let t = Self.translationState(row)
        let status: EntryStatus = row["status"] == "excluded" ? (row["excluded_reason"] == "paused" ? .paused : .known) : .active
        return EntryDetail(id: canonical, text: row["text"] ?? "", ipa: row["ipa"], note: row["note"], status: status,
                           needsCheck: row["needs_check"] == 1, translation: t, stage: Self.stage(row, translation: t),
                           createdAt: row["created_at"] ?? 0, senses: senses, contexts: contexts, tags: try tags(of: canonical), cards: cards)
    }

    /// The live canonical Entry a canonical Card belongs to; nil when the Card or its Entry is gone (Review, §7.8).
    public func cardEntry(_ card: ToriID) throws -> ToriID? {
        try ToriID.fetchOne(db, sql: """
            SELECT e.id FROM card c JOIN entry e ON e.id = c.canonical_entry_id WHERE c.id = ? AND \(Self.liveEntry)
            """, arguments: [card])
    }

    /// Live canonical Tags the Entry is a member of (OR of `present`), by tag key.
    public func tags(of entry: ToriID) throws -> [TagRow] {
        try Row.fetchAll(db, sql: """
            SELECT t.id, t.name FROM tag t WHERE t.deleted = 0 AND t.merged_into IS NULL AND EXISTS
            (SELECT 1 FROM entry_tag et WHERE et.canonical_entry_id = ? AND et.canonical_tag_id = t.id AND et.present = 1)
            ORDER BY t.name_key, t.id
            """, arguments: [entry]).map { TagRow(id: $0["id"], name: $0["name"] ?? "") }
    }

    /// All live canonical Tags by tag key.
    public func allTags() throws -> [TagRow] {
        try Row.fetchAll(db, sql: "SELECT id, name FROM tag WHERE deleted = 0 AND merged_into IS NULL ORDER BY name_key, id")
            .map { TagRow(id: $0["id"], name: $0["name"] ?? "") }
    }

    /// Entries waiting for enrichment (§6.4).
    public func pendingEnrichment() throws -> [ToriID] {
        try ToriID.fetchAll(db, sql: "SELECT id FROM entry e WHERE \(Self.liveEntry) AND e.enrichment_status = 'pending' ORDER BY e.created_at, e.id")
    }

    /// Entries enrichment gave up on; re-run when a new source appears (§6.4).
    public func unavailableEnrichment() throws -> [ToriID] {
        try ToriID.fetchAll(db, sql: "SELECT id FROM entry e WHERE \(Self.liveEntry) AND e.enrichment_status = 'unavailable' ORDER BY e.created_at, e.id")
    }

    // MARK: Progress (§14.1)

    public func progress(now: Int64, utcOffsetMin: Int) throws -> ProgressSummary {
        let today = DayModel.dayNumber(unixMs: now, utcOffsetMin: utcOffsetMin)
        let queue = try dailyQueue(now: now, utcOffsetMin: utcOffsetMin)
        let rows = try Row.fetchAll(db, sql: """
            SELECT e.status, e.excluded_reason, e.created_at,
              (SELECT group_concat(c.stage) FROM card c WHERE c.canonical_entry_id = e.id AND c.id = c.canonical_card_id) AS stages,
              (SELECT s.translation FROM sense s WHERE s.canonical_entry_id = e.id AND \(Self.liveSense) AND s.translation <> '' LIMIT 1) AS translation
            FROM entry e WHERE \(Self.liveEntry)
            """)
        let statuses = rows.map { r -> ProgressStats.EntryStatus in
            switch Self.stage(r, translation: Self.translationState(r)) {
            case .known: .alreadyKnown
            case .paused: .paused
            case .learning: .active(.learning)
            case .knownWell: .active(.knownWell)
            case .new, .needsTranslation: .active(.new)
            }
        }
        let logs = try queueInput().logs
        let sources = try Row.fetchAll(db, sql: """
            SELECT so.id, so.title, so.url, so.kind, (SELECT COUNT(DISTINCT c.canonical_entry_id) FROM context c
              JOIN source s0 ON s0.id = c.source_id JOIN entry e ON e.id = c.canonical_entry_id
              WHERE s0.canonical_id = so.id AND c.deleted = 0 AND c.merged_into IS NULL AND \(Self.liveEntry)) AS n
            FROM source so WHERE so.deleted = 0 AND so.merged_into IS NULL
            """).map { r in
            ProgressStats.SourceUsage(id: r["id"], title: r["title"], url: r["url"], isSuggested: r["kind"] == "suggested", entryCount: r["n"])
        }
        return ProgressSummary(today: ProgressStats.today(queue), vocabulary: ProgressStats.vocabulary(statuses),
                               activity: ProgressStats.activity(logs: logs, today: today),
                               capturedPerWeek: ProgressStats.capturedPerWeek(createdAt: rows.compactMap { $0["created_at"] },
                                                                              today: today, utcOffsetMin: utcOffsetMin),
                               topSources: ProgressStats.topSources(sources))
    }

    // MARK: Share Extension index (§5.4)

    public func vocabIndex(generatedAt: Int64) throws -> VocabIndex {
        let rows = try Row.fetchAll(db, sql: """
            SELECT e.id, e.match_key, e.status, e.excluded_reason,
              (SELECT group_concat(t, char(31)) FROM (SELECT s.translation AS t FROM sense s WHERE s.canonical_entry_id = e.id
                AND \(Self.liveSense) AND s.translation <> '' ORDER BY \(Self.senseOrder) LIMIT 3)) AS translations
            FROM entry e WHERE \(Self.liveEntry) AND e.match_key IS NOT NULL ORDER BY e.match_key, e.id
            """)
        let entries = rows.map { r in
            VocabIndex.Entry(matchKey: r["match_key"], entryId: r["id"],
                             translations: ((r["translations"] as String?) ?? "").split(separator: "\u{1F}").map(String.init),
                             status: r["status"] == "excluded" ? (r["excluded_reason"] == "paused" ? .paused : .known) : .active)
        }
        let tags = try Row.fetchAll(db, sql: "SELECT name_key, name FROM tag WHERE deleted = 0 AND merged_into IS NULL ORDER BY name_key, id")
            .map { VocabIndex.Tag(key: $0["name_key"] ?? "", name: $0["name"] ?? "") }
        return VocabIndex(generatedAt: generatedAt, entries: entries, tags: tags)
    }
}

extension ToriStore {
    /// Rewrites `vocab-index.json` and `widget-snapshot.json` in the App Group.
    public func writeAppGroupFiles(_ group: AppGroup, now: Int64, utcOffsetMin: Int) throws {
        let (index, snapshot) = try read { r in (try r.vocabIndex(generatedAt: now), try r.widgetSnapshot(now: now, utcOffsetMin: utcOffsetMin)) }
        try group.writeVocabIndex(index)
        try group.writeWidgetSnapshot(snapshot)
    }
}
