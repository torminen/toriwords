import Foundation
import GRDB
import ToriCore
import ToriShared

/// One capture (Add screen, Share Extension inbox): the §5.6 use case.
public struct CaptureInput: Hashable, Sendable {
    public var term: String
    public var capturedAt: Int64
    /// `typed` / `shared` / `text_selection` / `imported`.
    public var origin: String
    public var nativeLang: String
    public var targetLang: String
    public var senses: [NewSense]
    public var sentence: String?
    public var highlight: Capture.Highlight?
    public var source: SourceInput?
    public var tags: [String]
    public var resume: Bool

    public init(term: String, capturedAt: Int64, origin: String = "typed", nativeLang: String = "ru", targetLang: String = "en",
                senses: [NewSense] = [], sentence: String? = nil, highlight: Capture.Highlight? = nil, source: SourceInput? = nil,
                tags: [String] = [], resume: Bool = false) {
        self.term = term
        self.capturedAt = capturedAt
        self.origin = origin
        self.nativeLang = nativeLang
        self.targetLang = targetLang
        self.senses = senses
        self.sentence = sentence
        self.highlight = highlight
        self.source = source
        self.tags = tags
        self.resume = resume
    }

    /// Format-1 inbox file → capture (`typedTranslation` is a `user` Sense; a URL source is `web`, a title-only one `other`).
    public init(_ file: InboxFile) {
        var senses = file.chosenSenses.map { s in
            NewSense(translation: s.translation, definition: s.definition, partOfSpeech: s.pos,
                     source: s.provenance.kind == "wiktionary" ? .wiktionary : .user, dictVersion: s.provenance.dictVersion,
                     dictHeadwordKey: s.provenance.headwordKey, dictSenseOrdinal: s.provenance.senseOrdinal)
        }
        if let typed = file.typedTranslation, !typed.isEmpty { senses.append(NewSense(translation: typed)) }
        let source = file.source.flatMap { s -> SourceInput? in
            guard s.url != nil || s.title != nil else { return nil }
            return SourceInput(kind: s.url != nil ? .web : .other, url: s.url, title: s.title, app: s.app)
        }
        self.init(term: file.term, capturedAt: file.capturedAt, origin: file.origin, nativeLang: file.languagePair.native,
                  targetLang: file.languagePair.target, senses: senses, sentence: file.sentence, highlight: file.highlight,
                  source: source, tags: file.tags ?? [], resume: file.resume)
    }
}

public struct InboxImportResult: Equatable, Sendable {
    public var imported: [ToriID] = []
    /// Left in place: unknown format or unreadable.
    public var leftInPlace: [ToriID] = []
}

extension ToriStore {
    /// Runs a capture; returns the (possibly existing) Entry ID.
    @discardableResult
    public func capture(_ input: CaptureInput) throws -> ToriID {
        try write { tx in try Self.capture(tx, input) }
    }

    static func capture(_ tx: Tx, _ input: CaptureInput) throws -> ToriID {
        let db = tx.db
        let pair = ToriID.languagePair(native: input.nativeLang, target: input.targetLang)
        let entry: ToriID
        if let existing = try ToriID.fetchOne(db, sql: """
            SELECT id FROM entry WHERE \(DuplicateMerge.live) AND language_pair_id = ? AND match_key = ? ORDER BY id LIMIT 1
            """, arguments: [pair, TextKey.matchKey(input.term)]) {
            entry = existing
            if input.resume, try String.fetchOne(db, sql: "SELECT status FROM entry WHERE id = ?", arguments: [entry]) == "excluded" {
                try tx.set(.entry, entry, ["status": .string("active"), "excluded_reason": .null], rank: .user)
            }
        } else {
            entry = tx.newID()
            try tx.set(.entry, entry, [
                "language_pair_id": pair.wire, "text": .string(input.term), "status": .string("active"),
                "origin": .string(input.origin), "created_at": .int(input.capturedAt), "updated_at": .int(tx.now),
            ], rank: .user)
            try tx.set(.entry, entry, ["needs_check": .bool(false), "enrichment_status": .string("pending")], rank: .automatic)
        }

        let liveTranslations = Set(try String.fetchAll(db, sql: """
            SELECT translation FROM sense WHERE \(DuplicateMerge.live) AND (canonical_entry_id = ? OR entry_id = ?) AND translation IS NOT NULL
            """, arguments: [entry, entry]).map(TextKey.translationKey))
        var seen = liveTranslations
        for sense in input.senses {
            let key = TextKey.translationKey(sense.translation ?? "")
            if !key.isEmpty { guard seen.insert(key).inserted else { continue } }
            _ = try addSense(tx, entry: entry, sense, id: tx.newID(), rank: .user)
        }

        let sourceID = try input.source.map { try source(tx, $0) }
        _ = try addContext(tx, entry: entry, sentence: input.sentence, highlight: input.highlight, sourceID: sourceID,
                           capturedAt: input.capturedAt)
        for name in input.tags where !TextKey.tagKey(name).isEmpty {
            try setMembership(tx, entry: entry, tag: try tagID(tx, name: name), present: true)
        }
        let hasTranslation = try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM sense WHERE \(DuplicateMerge.live) AND (canonical_entry_id = ? OR entry_id = ?) AND translation <> '')
            """, arguments: [entry, entry]) ?? false
        if !hasTranslation {
            try tx.set(.entry, entry, ["enrichment_status": .string("pending")], rank: .automatic)
        }
        return entry
    }

    /// §5.6: imports every inbox file in capture-ID order, one transaction each, idempotent via `inbox_import`;
    /// files are deleted after commit; unknown formats stay.
    public func importInbox(_ inbox: Inbox) throws -> InboxImportResult {
        var result = InboxImportResult()
        for id in inbox.pending() {
            if try db.read({ try Bool.fetchOne($0, sql: "SELECT EXISTS (SELECT 1 FROM inbox_import WHERE inbox_id = ?)", arguments: [id]) }) == true {
                try inbox.delete(id)
                continue
            }
            guard case .capture(let file)? = try? inbox.read(id) else {
                result.leftInPlace.append(id)
                continue
            }
            try write { tx in
                _ = try Self.capture(tx, CaptureInput(file))
                try tx.db.execute(sql: "INSERT INTO inbox_import (inbox_id, imported_at) VALUES (?, ?)", arguments: [id, tx.now])
            }
            try inbox.delete(id)
            result.imported.append(id)
        }
        return result
    }
}
