import Foundation
import GRDB
import Testing
import ToriCore
import ToriShared
import ToriTestSupport
@testable import ToriStore

// MARK: Schema and launch

@Test func migrationsAndPragmas() throws {
    let s = try TestStore(launch: false)
    #expect(try s.scalar("SELECT version FROM schema_meta") == 1)
    #expect(try s.scalar("PRAGMA journal_mode") == "wal")
    #expect(try s.scalar("PRAGMA synchronous") == 1)
    #expect(try s.scalar("PRAGMA foreign_keys") == 1)
    #expect(try s.scalar("PRAGMA encoding") == "UTF-8")
    let tables: [String] = try s.store.db.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") }
    #expect(Set(tables).isSuperset(of: RecordType.all.map(\.name) + ["pending_changes", "sync_state", "inbox_import", "schema_meta"]))
    // Reopening runs no migration twice.
    _ = try ToriStore(path: s.dir.appendingPathComponent("user.sqlite").path)
}

@Test func launchFreshThenRestore() throws {
    let s = try TestStore(launch: false)
    #expect(try s.store.launch(deviceMarker: s.marker, displayName: "iPhone") == .freshInstall)
    let first = try #require(try s.store.thisDeviceID())
    #expect(try Data(contentsOf: s.marker) == Data(first.bytes))
    #expect(try s.scalar("SELECT new_words_per_day FROM settings WHERE id = ?", [ToriID.settings]) == 10)
    #expect(try s.scalar("SELECT native_lang FROM language_pair WHERE id = ?", [ToriID.languagePair(native: "ru", target: "en")]) == "ru")
    #expect((try s.scalar("SELECT field_clocks FROM settings") as String?)?.contains("\"u\":0") == true)

    #expect(try s.store.launch(deviceMarker: s.marker, displayName: "iPhone") == .existing)

    // Restored from a backup: the marker (excluded from backup) is missing; token and system fields are stale.
    try s.activateCloud()
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0))
    try s.store.applyCloudChanges([], meta: [e: Data([1])], token: "dG9r")
    try s.store.recordSaved(try s.store.pendingPush().rows, meta: [e: Data([2])])
    try FileManager.default.removeItem(at: s.marker)
    #expect(try s.store.launch(deviceMarker: s.marker, displayName: "iPhone") == .restoredFromBackup)
    let second = try #require(try s.store.thisDeviceID())
    #expect(second != first)
    #expect(try s.scalar("SELECT is_this_device FROM device WHERE id = ?", [first]) == 0)
    #expect(try s.store.syncState(.changeToken) == nil && s.store.cloudMeta([e]).isEmpty)
    #expect(try s.store.syncState(.cloudUser) == "user-1")
    #expect(try s.store.pendingPush().records.contains { $0.id == e })
}

// MARK: Text order through the real A–Z query

@Test(arguments: Fixture.cases("normalization/text-order.json").filter { $0["prefix"].string == nil })
func alphabeticalQueryOrder(_ c: FixtureCase) throws {
    let s = try TestStore()
    for (i, key) in c["keys"].array.enumerated() {
        let id = try s.store.capture(CaptureInput(term: "w\(i)", capturedAt: t0))
        try s.store.db.write { try $0.execute(sql: "UPDATE entry SET match_key = ? WHERE id = ?", arguments: [key.string!, id]) }
    }
    let ordered = try s.store.read { try $0.words(WordsQuery(sort: .alphabetical)) }
    let keys: [String] = try ordered.map { try #require(try s.scalar("SELECT match_key FROM entry WHERE id = ?", [$0.id])) }
    #expect(keys.map { Array($0.utf8) } == c["expected"].array.map { Array($0.string!.utf8) })
}

// MARK: Clocks and outbox

@Test func outboxOnlyWhileCloudActiveAndNotDeleted() throws {
    let s = try TestStore()
    let a = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать")]))
    #expect(try s.store.pendingRecordCount() == 0)
    let clocks = try #require(JSONText.decode([String: FieldClock].self, try s.scalar("SELECT field_clocks FROM entry WHERE id = ?", [a])))
    #expect(clocks["text"]?.u == 1 && clocks["enrichment_status"]?.u == 0 && clocks["needs_check"]?.u == 0)

    try s.activateCloud()
    let initial = try s.store.pendingPush()
    try s.store.recordSaved(initial.rows, meta: Dictionary(uniqueKeysWithValues: initial.records.map { ($0.id, Data([0])) }))
    #expect(try s.store.pendingRecordCount() == 0)
    s.clock.ms += 1
    try s.store.setEntryNote(a, "note")
    let rows = try s.rows("SELECT type, field FROM pending_changes").map { "\($0["type"] as String).\($0["field"] as String)" }
    #expect(Set(rows) == ["entry.note", "entry.updated_at"])
    let push = try s.store.pendingPush()
    #expect(push.records.count == 1 && push.records[0].fields.keys.contains("text"), "full envelope")

    // Ack removes only rows whose clock is unchanged; the system fields are stored.
    s.clock.ms += 1
    try s.store.setEntryNote(a, "newer")
    try s.store.recordSaved(push.rows, meta: [a: Data([7])])
    #expect(try s.store.cloudMeta([a]) == [a: Data([7])])
    #expect(try s.rows("SELECT field FROM pending_changes").map { $0["field"] as String }.sorted() == ["note", "updated_at"])
    let all = try s.store.pendingPush()
    try s.store.recordSaved(all.rows, meta: [a: Data([8])])
    #expect(try s.store.pendingRecordCount() == 0)

    // iCloud data deleted: no outbox rows, clocks still stamped.
    try s.store.markCloudDeleted()
    try s.store.setEntryNote(a, "local edit")
    #expect(try s.store.pendingRecordCount() == 0)
    #expect(try s.scalar("SELECT note FROM entry WHERE id = ?", [a]) == "local edit")
    #expect(try s.store.cloudMeta([a]).isEmpty)
}

@Test func automaticWriteNeverOverridesUserValue() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0))
    try s.store.fillAutomaticSense(e, .tr("бежать"))
    let auto = ToriID.autoSense(entry: e, ordinal: 0)
    try s.store.editSense(auto, translation: "", definition: nil, partOfSpeech: nil)  // user cleared it
    try s.store.fillAutomaticSense(e, .tr("бегать"))
    #expect(try s.scalar("SELECT translation FROM sense WHERE id = ?", [auto]) == "")
    let row = try #require(try s.store.read { try $0.words(WordsQuery(filter: .needsTranslation)) }.first)
    #expect(row.translation == .none)
}

@Test func clockAheadRecoveryRestampsPendingFields() throws {
    let s = try TestStore()
    try s.activateCloud()
    s.clock.ms = t0 + 10 * HLCState.hourMs  // device clock ran ahead
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0))
    s.clock.ms = t0
    #expect(try s.store.recoverClockAhead(lastServerTime: t0))
    let clocks = try s.rows("SELECT clock FROM pending_changes").map { HLCTimestamp($0["clock"] as String)! }
    #expect(clocks.allSatisfy { $0.ms == t0 })
    let fields = try #require(JSONText.decode([String: FieldClock].self, try s.scalar("SELECT field_clocks FROM entry WHERE id = ?", [e])))
    #expect(fields.values.allSatisfy { HLCTimestamp($0.c)!.ms == t0 })
    #expect(try !s.store.recoverClockAhead(lastServerTime: t0))
}

// MARK: Duplicate merge

@Test func mergeByEditIsAskedThenDeterministic() throws {
    let s = try TestStore()
    try s.activateCloud()
    let run = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать")]))
    s.clock.ms += 1000
    let walk = try s.store.capture(CaptureInput(term: "walk", capturedAt: t0, senses: [.tr("идти")]))
    #expect(try s.store.setEntryText(walk, "Run") == .duplicate(of: run))
    #expect(try s.scalar("SELECT text FROM entry WHERE id = ?", [walk]) == "walk")

    #expect(try s.store.setEntryText(walk, "Run", mergeIfDuplicate: true) == .saved)
    let survivor = min(run, walk), loser = max(run, walk)
    #expect(try s.scalar("SELECT merged_into FROM entry WHERE id = ?", [loser]) == survivor)
    #expect(try s.scalar("SELECT COUNT(*) FROM pending_changes WHERE record_id = ? AND field = '_mergedInto'", [loser]) == 1)
    let words = try s.store.read { try $0.words(WordsQuery()) }
    #expect(words.map(\.id) == [survivor])
    let detail = try #require(try s.store.read { try $0.entry(loser) })
    #expect(detail.id == survivor)
    #expect(detail.senses.map(\.translation) == ["бежать", "идти"])
    // The survivor took the loser's newer user text ("Run", rank 1, later clock).
    #expect(detail.text == "Run")
    // Cards resolve to the survivor's canonical Cards only.
    #expect(Set(detail.cards.map(\.id)) == [ToriID.card(entry: survivor, direction: .recognition), .card(entry: survivor, direction: .recall)])
}

@Test func postPullMergePicksSmallestIDAndKeepsHistory() throws {
    let phone = try TestStore(now: t0 + 60_000)
    let tablet = try TestStore(now: t0)  // earlier clock → smaller UUIDv7
    let mine = try phone.store.capture(CaptureInput(term: "take off", capturedAt: t0, senses: [.tr("взлетать")]))
    let theirs = try tablet.store.capture(CaptureInput(term: "Take  off", capturedAt: t0, senses: [.tr("снимать")]))
    #expect(theirs < mine)
    let card = ToriID.card(entry: mine, direction: .recognition)
    try phone.store.commitAnswer(card: card, rating: .remembered, reviewedAt: t0 + 120_000, utcOffsetMin: 0, answerMs: 1000)

    try phone.store.applyCloudChanges(try tablet.records(), token: "1")
    #expect(try phone.scalar("SELECT merged_into FROM entry WHERE id = ?", [mine]) == theirs)
    #expect(try phone.store.syncState(.changeToken) == "1")
    let detail = try #require(try phone.store.read { try $0.entry(mine) })
    #expect(detail.id == theirs)
    #expect(Set(detail.senses.compactMap(\.translation)) == ["взлетать", "снимать"])
    // The answer on the loser's Card now counts for the survivor's canonical Card.
    let canonical = ToriID.card(entry: theirs, direction: .recognition)
    #expect(detail.cards.first { $0.direction == .recognition }?.reps == 1)
    #expect(try phone.scalar("SELECT canonical_card_id FROM review_log") == canonical)
    #expect(try phone.store.read { try $0.words(WordsQuery()) }.count == 1)
}

@Test func tagsMergeByKeyAndMembershipIsOr() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, tags: ["Work"]))
    let f = try s.store.capture(CaptureInput(term: "walk", capturedAt: t0))
    try s.store.tag([f], name: "home")
    let home = try #require(try s.store.read { try $0.allTags() }.first { $0.name == "home" })
    #expect(try s.store.renameTag(home.id, to: "WORK") != .saved)
    #expect(try s.store.renameTag(home.id, to: "WORK", mergeIfDuplicate: true) == .saved)
    let tags = try s.store.read { try $0.allTags() }
    #expect(tags.count == 1)
    let work = tags[0].id
    #expect(Set(try s.store.read { try $0.words(WordsQuery(tags: [work])) }.map(\.id)) == [e, f])
    try s.store.untag(f, tag: work)
    #expect(try s.store.read { try $0.words(WordsQuery(tags: [work])) }.map(\.id) == [e])
}

// MARK: Pull: orphans, tombstones

@Test func orphansThenParentEqualsSinglePage() throws {
    let source = try TestStore(now: t0)
    let e = try source.store.capture(CaptureInput(term: "take off", capturedAt: t0, senses: [.tr("взлетать")],
                                                  sentence: "The plane took off late.", highlight: .init(offset: 10, length: 8),
                                                  source: SourceInput(kind: .web, url: "https://example.com/a?utm_source=x", title: "News"),
                                                  tags: ["travel"]))
    for (i, card) in [CardDirection.recognition, .recall, .cloze].enumerated() {
        try source.store.commitAnswer(card: .card(entry: e, direction: card), rating: i == 1 ? .forgot : .remembered,
                                      reviewedAt: t0 + Int64(i) * 1000, utcOffsetMin: 180, answerMs: 900)
    }
    let records = try source.records()
    let parents: Set = ["entry", "card", "tag", "source", "language_pair", "settings"]

    let one = try TestStore(now: t0 + 1)
    try one.store.applyCloudChanges(records, token: "1")
    let two = try TestStore(now: t0 + 1)
    try two.store.applyCloudChanges(records.filter { !parents.contains($0.type) }, token: "1")
    #expect(try two.store.read { try $0.words(WordsQuery()) }.isEmpty)  // orphans hidden
    try two.store.applyCloudChanges(records.filter { parents.contains($0.type) }, token: "2")

    #expect(try one.dump().filter { !$0.hasPrefix("settings") && !$0.hasPrefix("language_pair") }
            == two.dump().filter { !$0.hasPrefix("settings") && !$0.hasPrefix("language_pair") })
    let detail = try #require(try two.store.read { try $0.entry(e) })
    #expect(detail.cards.map(\.reps) == [1, 1, 1])
    #expect(detail.contexts.first?.sourceTitle == "News")
    #expect(detail.tags.map(\.name) == ["travel"])
    // Same canonical card state as on the source device.
    #expect(try one.rows("SELECT id, stability, due_day FROM card ORDER BY id").map { "\($0)" }
            == source.rows("SELECT id, stability, due_day FROM card ORDER BY id").map { "\($0)" })
}

@Test func deleteWinsHidesPurgesAndDropsLateChildren() throws {
    let a = try TestStore(now: t0)
    let e = try a.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать")]))
    let b = try TestStore(now: t0)
    try b.store.applyCloudChanges(try a.records(), token: "1")

    // A adds a Sense offline; B deletes (signed out → children purged at once).
    let lateSense = try a.store.addSense(to: e, .tr("бегать"))
    try b.store.deleteEntries([e])
    #expect(try b.store.read { try $0.words(WordsQuery()) }.isEmpty)
    #expect(try b.scalar("SELECT COUNT(*) FROM sense") == 0)
    #expect(try b.scalar("SELECT COUNT(*) FROM card") == 0)

    try b.store.applyCloudChanges(try a.store.db.read { db in [try RecordIO.load(db, .sense, lateSense)!] }, token: "2")
    #expect(try b.scalar("SELECT COUNT(*) FROM sense") == 0)

    // The tombstone reaches A and wins over its offline edit.
    let tombstone = try b.store.db.read { try RecordIO.load($0, .entry, e)! }
    #expect(tombstone.deleted && tombstone.fields.isEmpty)
    try a.store.applyCloudChanges([tombstone], token: "1")
    #expect(try a.store.read { try $0.words(WordsQuery()) }.isEmpty)
    #expect(try a.store.read { try $0.entry(e) } == nil)
}

@Test func unknownFieldsAndTypesAreKept() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0))
    var record = try s.store.db.read { try RecordIO.load($0, .entry, e)! }
    let clock = HLCTimestamp(ms: t0 + 5000, counter: 0, node: 7)
    record.fields["future_field"] = FieldVersion(value: .string("x"), clock: clock, rank: .user)
    record.schema = 2
    let unknown = SyncRecord(id: .v5("x"), type: "deck", schema: 1, owner: nil, deleted: false, mergedInto: nil, fields: [:])
    let result = try s.store.applyCloudChanges([record, unknown], token: "1")
    #expect(result.skippedUnknownTypes == ["deck"])
    try s.activateCloud()
    try s.store.markAllPending()
    let pushed = try #require(try s.store.pendingPush().records.first { $0.id == e })
    #expect(pushed.fields["future_field"] == FieldVersion(value: .string("x"), clock: clock, rank: .user))
    #expect(pushed.schema == 2)
}

// MARK: Scheduler cache

@Test func incrementalAnswerEqualsFullReplayAndParamsRebuild() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать")]))
    let card = ToriID.card(entry: e, direction: .recall)
    let answers: [(Int, Rating)] = [(0, .remembered), (0, .forgot), (1, .remembered), (4, .remembered), (13, .forgot), (14, .remembered)]
    for (day, rating) in answers {
        try s.store.commitAnswer(card: card, rating: rating, reviewedAt: t0 + Int64(day) * 86_400_000 + 1, utcOffsetMin: 180, answerMs: 2000)
    }
    // An out-of-order (older) answer takes the full-replay path.
    try s.store.commitAnswer(card: card, rating: .remembered, reviewedAt: t0 + 2 * 86_400_000, utcOffsetMin: 180, answerMs: nil)

    func expected(_ p: FSRSParameters) throws -> CardState? {
        let logs = try s.rows("SELECT id, reviewed_at, utc_offset_min, rating FROM review_log").map {
            ReviewLogInput(id: $0["id"], cardID: card, reviewedAt: $0["reviewed_at"], utcOffsetMin: $0["utc_offset_min"],
                           rating: Rating(rawValue: $0["rating"]))
        }
        return FSRS.replay(cardID: card, logs: logs, p)
    }
    func cached() throws -> Row { try #require(try s.rows("SELECT * FROM card WHERE id = ?", [card]).first) }

    var want = try #require(try expected(.default))
    var row = try cached()
    #expect(row["stability"] == want.stability && row["difficulty"] == want.difficulty)
    #expect(row["due_day"] == want.dueDay && row["reps"] == want.reps)
    #expect(row["lapses"] == want.lapses && row["stage"] == want.stage.rawValue)

    var p = FSRSParameters.default
    p.desiredRetention = 0.85
    try s.store.setSchedulerParameters(p, paramsID: "custom-1")
    want = try #require(try expected(p))
    row = try cached()
    #expect(row["stability"] == want.stability && row["due_day"] == want.dueDay && row["params_id"] == "custom-1")
}

// MARK: Cards and enrichment

@Test func cardsCreatedWhenReviewableWithClozeForHighlightedSentence() throws {
    let s = try TestStore()
    let plain = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать")], sentence: "They walk."))
    let cloze = try s.store.capture(CaptureInput(term: "walk", capturedAt: t0, senses: [.tr("идти")], sentence: "They walk.",
                                                 highlight: .init(offset: 5, length: 4)))
    let pending = try s.store.capture(CaptureInput(term: "jump", capturedAt: t0))
    func directions(_ e: ToriID) throws -> [CardDirection] { try #require(try s.store.read { try $0.entry(e) }).cards.map(\.direction) }
    #expect(try directions(plain) == [.recognition, .recall])
    #expect(try directions(cloze) == [.recognition, .recall, .cloze])
    #expect(try directions(pending).isEmpty)
    #expect(try s.store.read { try $0.entry(pending) }?.translation == .pending)
    #expect(try s.store.read { try $0.pendingEnrichment() } == [pending])

    try s.store.fillAutomaticSense(pending, .tr("прыгать"))
    #expect(try directions(pending) == [.recognition, .recall])
    #expect(try s.store.read { try $0.words(WordsQuery(filter: .checkTranslation)) }.map(\.id) == [pending])
    try s.store.commitAnswer(card: .card(entry: pending, direction: .recall), rating: .remembered, reviewedAt: t0, utcOffsetMin: 0, answerMs: 1)
    #expect(try s.store.read { try $0.words(WordsQuery(filter: .checkTranslation)) }.isEmpty)
    let clocks = try #require(JSONText.decode([String: FieldClock].self, try s.scalar("SELECT field_clocks FROM entry WHERE id = ?", [pending])))
    #expect(clocks["needs_check"]?.u == 0)

    for _ in 0..<3 { try s.store.recordEnrichmentFailure(plain) }  // has a translation: state stays "has"
    let none = try s.store.capture(CaptureInput(term: "fly", capturedAt: t0))
    for _ in 0..<3 { try s.store.recordEnrichmentFailure(none) }
    #expect(try s.store.read { try $0.entry(none) }?.translation == .notFound)
}

// MARK: Inbox

@Test func inboxImportIsIdempotentAndOrdered() throws {
    let s = try TestStore()
    let group = AppGroup(root: s.dir.appendingPathComponent("group"))
    let inbox = group.inbox
    let first = ToriID.v7(unixMs: t0, randA: 1, randB: 1), second = ToriID.v7(unixMs: t0 + 1, randA: 1, randB: 1)
    let file = InboxFile(captureId: first, capturedAt: t0, utcOffsetMin: 180, term: "take off",
                         sentence: "The plane took off an hour late.", highlight: .init(offset: 10, length: 8),
                         source: .init(url: "https://example.com/a", title: "News"), tags: ["work"],
                         chosenSenses: [.init(translation: "взлетать", provenance: .init(kind: "wiktionary", dictVersion: "2026.11.1",
                                                                                         headwordKey: "take off", senseOrdinal: 0))])
    try inbox.write(file)
    var again = file
    again.captureId = second
    again.chosenSenses = [.init(translation: "Взлетать", provenance: .init(kind: "user"))]  // same translation key
    again.typedTranslation = "уходить"
    again.resume = true
    try inbox.write(again)
    let unknown = ToriID.v7(unixMs: t0 + 2, randA: 1, randB: 1)
    try Data(#"{"format": 9}"#.utf8).write(to: inbox.url(for: unknown))

    let result = try s.store.importInbox(inbox)
    #expect(result.imported == [first, second] && result.leftInPlace == [unknown])
    #expect(inbox.pending() == [unknown])
    let words = try s.store.read { try $0.words(WordsQuery()) }
    #expect(words.count == 1)
    let detail = try #require(try s.store.read { try $0.entry(words[0].id) })
    #expect(detail.senses.compactMap(\.translation) == ["взлетать", "уходить"])
    #expect(detail.contexts.count == 1 && detail.tags.map(\.name) == ["work"])
    #expect(detail.createdAt == t0)
    #expect(try s.scalar("SELECT origin FROM entry") == "shared")

    // Crash between commit and delete: the file reappears and is skipped.
    try inbox.write(file)
    let before = try s.dump()
    #expect(try s.store.importInbox(inbox).imported.isEmpty)
    #expect(inbox.pending() == [unknown])
    #expect(try s.dump() == before)
}

// MARK: Words list and search

@Test func searchUsesFoldsAndEscapesLike() throws {
    let s = try TestStore()
    let yolka = try s.store.capture(CaptureInput(term: "Ёлка", capturedAt: t0, senses: [.tr("fir tree")]))
    let pct = try s.store.capture(CaptureInput(term: "100% sure", capturedAt: t0 + 1, senses: [.tr("уверен")],
                                               sentence: "I am ABC Sure."))
    let other = try s.store.capture(CaptureInput(term: "1000 sure", capturedAt: t0 + 2))
    func search(_ q: String) throws -> Set<ToriID> { Set(try s.store.read { try $0.words(WordsQuery(search: q)) }.map(\.id)) }
    #expect(try search("ЕЛК") == [yolka])
    #expect(try search("Fir") == [yolka])
    #expect(try search("abc") == [pct])
    #expect(try search("0%") == [pct])
    #expect(try search("1_0") == [])
    #expect(try search("уверен") == [pct])
    #expect(try search("  ") == [yolka, pct, other])
}

@Test func wordsFiltersAndSorts() throws {
    let s = try TestStore()
    let b = try s.store.capture(CaptureInput(term: "b word", capturedAt: t0, senses: [.tr("б")],
                                             source: SourceInput(kind: .other, title: "The Bear S2E3")))
    let a = try s.store.capture(CaptureInput(term: "alpha", capturedAt: t0 + 1, senses: [.tr("а")]))
    let c = try s.store.capture(CaptureInput(term: "Charlie", capturedAt: t0 + 2))
    try s.store.setStatus([a], .known)
    func ids(_ q: WordsQuery) throws -> [ToriID] { try s.store.read { try $0.words(q) }.map(\.id) }
    #expect(try ids(WordsQuery()) == [c, a, b])
    #expect(try ids(WordsQuery(sort: .alphabetical)) == [a, b, c])
    #expect(try ids(WordsQuery(filter: .needsTranslation)) == [c])
    #expect(try ids(WordsQuery(filter: .phrases)) == [b])
    #expect(try ids(WordsQuery(filter: .stage(.known))) == [a])
    #expect(try ids(WordsQuery(filter: .stage(.new))) == [b])
    #expect(try ids(WordsQuery(sort: .nextDue)) == [b, c, a])
    let source = try #require(try s.scalar("SELECT id FROM source") as ToriID?)
    #expect(try ids(WordsQuery(source: source)) == [b])
    // The same title-only source is reused by key.
    _ = try s.store.capture(CaptureInput(term: "delta", capturedAt: t0, source: SourceInput(kind: .other, title: " the bear s2e3 ")))
    #expect(try s.scalar("SELECT COUNT(*) FROM source") == 1)
}

// MARK: Home, widget, Share index, observation

@Test func homeSnapshotIndexAndObservation() async throws {
    let s = try TestStore()
    var updates = s.store.observe { try $0.words(WordsQuery()).count }.makeAsyncIterator()
    #expect(try await updates.next() == 0)
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать"), .tr("бегать"), .tr("течь"), .tr("работать")]))
    #expect(try await updates.next() == 1)
    try s.store.tag([e], name: "Work")

    let queue = try s.store.read { try $0.dailyQueue(now: t0, utcOffsetMin: 0) }
    #expect(queue.newCount == 1 && queue.homeState == .due)  // sibling filter: one Card per Entry per day
    let group = AppGroup(root: s.dir.appendingPathComponent("group"))
    try s.store.writeAppGroupFiles(group, now: t0, utcOffsetMin: 0)
    #expect(try group.readWidgetSnapshot()?.days.first?.newAvailable == 1)
    let index = try #require(try group.readVocabIndex())
    #expect(index.entries == [VocabIndex.Entry(matchKey: "run", entryId: e, translations: ["бежать", "бегать", "течь"], status: .active)])
    #expect(index.tags == [VocabIndex.Tag(key: "work", name: "Work")])

    let progress = try s.store.read { try $0.progress(now: t0, utcOffsetMin: 0) }
    #expect(progress.vocabulary.new == 1 && progress.capturedPerWeek.last == 1)
}

// MARK: Backup

@Test func exportRestoreRoundTripIsIdempotent() throws {
    let a = try TestStore()
    let e = try a.store.capture(CaptureInput(term: "take off", capturedAt: t0, senses: [.tr("взлетать")], sentence: "It took off.",
                                             tags: ["travel"]))
    let gone = try a.store.capture(CaptureInput(term: "gone", capturedAt: t0, senses: [.tr("ушёл")]))
    try a.store.commitAnswer(card: .card(entry: e, direction: .recognition), rating: .remembered, reviewedAt: t0, utcOffsetMin: 0, answerMs: 5)
    let backup = try a.store.exportBackup(attribution: "Wiktionary, CC BY-SA 4.0")
    let wrapper = try JSONDecoder().decode(Backup.self, from: backup)
    #expect(wrapper.format == "toriwords-backup" && wrapper.version == 1 && wrapper.protocol == 1)

    let b = try TestStore(now: t0 + 1)
    try b.activateCloud()
    #expect(try b.store.restore(backup) == RestoreSummary(imported: 2, merged: 0, deletedEarlier: 0))
    #expect(try b.store.pendingRecordCount() > 0)
    #expect(try a.store.read { try $0.entry(e) }?.cards == b.store.read { try $0.entry(e) }?.cards)
    #expect(try a.store.read { try $0.words(WordsQuery()) } == b.store.read { try $0.words(WordsQuery()) })

    let before = try b.dump()
    #expect(try b.store.restore(backup) == RestoreSummary())
    #expect(try b.dump() == before)

    try b.store.deleteEntries([gone])
    #expect(try b.store.restore(backup).deletedEarlier == 1)
    #expect(try b.store.read { try $0.entry(gone) } == nil)

    #expect(throws: StoreError.notABackup) { try b.store.restore(Data("{}".utf8)) }
    var newer = try JSONSerialization.jsonObject(with: backup) as! [String: Any]
    newer["version"] = 2
    #expect(throws: StoreError.updateRequired) { try b.store.restore(try JSONSerialization.data(withJSONObject: newer)) }

    let csv = try a.store.exportCSV(utcOffsetMin: 0)
    #expect(csv.containsWiktionary)
    #expect(csv.csv.hasPrefix("text,translations,definitions,sentence,source,tags,stage,created\r\n"))
    #expect(csv.csv.contains("take off,взлетать,,It took off.,,travel,learning,2025-11-10\r\n"))
}

@Test func removeAllDataRecreatesDefaultsAndClearsCloudState() throws {
    let s = try TestStore()
    try s.activateCloud()
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать")]))
    try s.store.applyCloudChanges([], meta: [e: Data([1])], token: "dG9r")
    try s.store.removeAllDataFromDevice()
    #expect(try s.store.syncState(.changeToken) == nil && s.store.cloudMeta([e]).isEmpty)
    #expect(try s.scalar("SELECT COUNT(*) FROM entry") == 0 && s.scalar("SELECT COUNT(*) FROM card") == 0)
    #expect(try s.scalar("SELECT COUNT(*) FROM settings") == 1 && s.scalar("SELECT COUNT(*) FROM language_pair") == 1)
    #expect(try s.store.pendingRecordCount() == 0)
    #expect(try s.store.thisDeviceID() != nil)
}

@Test func cardEntryResolvesLiveEntriesOnly() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [.tr("бежать")]))
    let card = ToriID.card(entry: e, direction: .recall)
    #expect(try s.store.read { try $0.cardEntry(card) } == e)
    try s.store.deleteEntries([e])
    #expect(try s.store.read { try $0.cardEntry(card) } == nil)
}

@Test func exportFileNamesUseTheLocalDay() {
    let date = Date(timeIntervalSince1970: Double(t0) / 1000) // 2025-11-10 12:00 UTC
    #expect(ExportFile.name(.backup, at: date, timeZone: TimeZone(identifier: "UTC")!) == "ToriWords-backup-2025-11-10.json")
    #expect(ExportFile.name(.csv, at: date, timeZone: TimeZone(identifier: "Pacific/Kiritimati")!) == "ToriWords-2025-11-11.csv")
}

@Test func csvExportCarriesAttributionOnlyWithWiktionaryText() throws {
    let s = try TestStore()
    _ = try s.store.capture(CaptureInput(term: "run", capturedAt: t0, senses: [NewSense(translation: "бежать", source: .user)]))
    let plain = String(decoding: try ExportFile.data(.csv, from: s.store, attribution: "Wiktionary, CC BY-SA", utcOffsetMin: 0), as: UTF8.self)
    #expect(!plain.contains("Wiktionary"))

    _ = try s.store.capture(CaptureInput(term: "go", capturedAt: t0, senses: [NewSense(translation: "идти", source: .wiktionary)]))
    let csv = String(decoding: try ExportFile.data(.csv, from: s.store, attribution: "Wiktionary, CC BY-SA", utcOffsetMin: 0), as: UTF8.self)
    #expect(csv.hasSuffix("\r\n\"Wiktionary, CC BY-SA\"\r\n"))

    let backup = try JSONDecoder().decode(Backup.self, from: ExportFile.data(.backup, from: s.store, attribution: "W", utcOffsetMin: 0))
    #expect(backup.attribution == "W")
}

@Test func newWordsPerDayIsClampedToTheSettingRange() throws {
    let s = try TestStore()
    try s.store.setNewWordsPerDay(99)
    #expect(try s.store.read { try $0.newWordsPerDay() } == ToriStore.newWordsPerDayRange.upperBound)
    try s.store.setNewWordsPerDay(-1)
    #expect(try s.store.read { try $0.newWordsPerDay() } == 0)
}

@Test func addQueriesFindSavedWordsAndCountTags() throws {
    let s = try TestStore()
    let a = try s.store.capture(CaptureInput(term: "Mortgage", capturedAt: t0, tags: ["Home", "money"]))
    let b = try s.store.capture(CaptureInput(term: "mortgage rate", capturedAt: t0, tags: ["money"]))
    _ = try s.store.capture(CaptureInput(term: "more", capturedAt: t0))
    let c = try s.store.capture(CaptureInput(term: "mortal", capturedAt: t0, tags: ["money"]))
    try s.store.deleteEntries([c])
    #expect(try s.store.read { try $0.vocabularyMatches(prefix: "MORT") }.map(\.id) == [a, b])
    #expect(try s.store.read { try $0.vocabularyMatches(prefix: " ") }.isEmpty)
    #expect(try s.store.read { try $0.entryID(matching: " mortgage. ") } == a)
    #expect(try s.store.read { try $0.entryID(matching: "mortal") } == nil)
    let tags = try s.store.read { try $0.allTags() }
    let counts = try s.store.read { try $0.tagCounts() }
    #expect(Dictionary(uniqueKeysWithValues: tags.map { ($0.name, counts[$0.id] ?? 0) }) == ["Home": 1, "money": 2])
}

// MARK: Entry edit mode

@Test func entryDraftDetectsChangesIgnoringBlankRows() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "bank", capturedAt: t0, senses: [.tr("банк")], sentence: "A bank."))
    let detail = try #require(try s.store.read { try $0.entry(e) })
    var d = EntryDraft(detail)
    #expect(!d.hasChanges(from: detail))
    d.meanings.append(.init())
    d.sentences.append(.init(text: "  "))
    #expect(!d.hasChanges(from: detail))
    d.note = "money"
    #expect(d.hasChanges(from: detail))
    d.text = " ... "
    #expect(!d.canSave)
}

@Test func entryDraftSaveAppliesEditsInOrder() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "bank", capturedAt: t0, senses: [.tr("банк"), .tr("берег"), .tr("отмель")],
                                             sentence: "A river bank.", tags: ["money", "nature"]))
    let detail = try #require(try s.store.read { try $0.entry(e) })
    var d = EntryDraft(detail)
    d.text = "Bank"
    d.ipa = " /bæŋk/ "
    d.meanings.remove(at: 2)                       // delete "отмель"
    d.meanings[1].translation = "берег реки"       // edit
    d.meanings.insert(.init(translation: "крен"), at: 0) // add at the top
    d.sentences.removeAll()
    d.sentences.append(.init(text: "The bank was closed.", source: "News"))
    d.tags = ["Money", "travel"]
    #expect(try s.store.save(d, original: detail) == .saved)
    let after = try #require(try s.store.read { try $0.entry(e) })
    #expect(after.text == "Bank" && after.ipa == "/bæŋk/")
    #expect(after.senses.map(\.translation) == ["крен", "банк", "берег реки"])
    #expect(after.senses[0].translationSource == .user && after.senses[1].translationSource == .wiktionary)
    #expect(after.contexts.map(\.sentence) == ["The bank was closed."])
    #expect(after.contexts[0].highlight == Capture.Highlight(offset: 4, length: 4) && after.contexts[0].sourceTitle == "News")
    #expect(after.tags.map(\.name) == ["money", "travel"])
}

@Test func entryDraftSuggestedMeaningKeepsProvenanceUntilEdited() throws {
    let s = try TestStore()
    let e = try s.store.capture(CaptureInput(term: "bank", capturedAt: t0, senses: [.tr("банк")]))
    let detail = try #require(try s.store.read { try $0.entry(e) })
    let dict = { (tr: String) in NewSense(translation: tr, definition: "edge of a river", partOfSpeech: "noun", source: .wiktionary,
                                          dictVersion: "1", dictHeadwordKey: "bank", dictSenseOrdinal: 2) }
    var d = EntryDraft(detail)
    d.meanings.append(.init(suggested: dict("берег")))
    var edited = EntryDraft.Meaning(suggested: dict("отмель"))
    edited.translation = "мель"
    d.meanings.append(edited)
    #expect(try s.store.save(d, original: detail) == .saved)
    let after = try #require(try s.store.read { try $0.entry(e) })
    #expect(after.senses.map(\.translation) == ["банк", "берег", "мель"])
    #expect(after.senses[1].translationSource == .wiktionary && after.senses[1].definition == "edge of a river")
    #expect(after.senses[2].translationSource == .user)
}

@Test func entryDraftDuplicateTextWritesNothingUntilMergeConfirmed() throws {
    let s = try TestStore()
    let a = try s.store.capture(CaptureInput(term: "colour", capturedAt: t0, senses: [.tr("цвет")]))
    let b = try s.store.capture(CaptureInput(term: "color", capturedAt: t0 + 1, senses: [.tr("окраска")]))
    let detail = try #require(try s.store.read { try $0.entry(b) })
    var d = EntryDraft(detail)
    d.text = "Colour"
    d.note = "spelling"
    #expect(try s.store.save(d, original: detail) == .duplicate(of: a))
    #expect(try s.store.read { try $0.entry(b) }?.note == nil)
    #expect(try s.store.save(d, original: detail, mergeIfDuplicate: true) == .saved)
    let merged = try #require(try s.store.read { try $0.entry(b) })
    #expect(Set(merged.senses.compactMap(\.translation)) == ["цвет", "окраска"])
    #expect(try s.store.read { try $0.words(WordsQuery()) }.count == 1)
}

// MARK: Bulk actions (Words select mode)

@Test func bulkStatusAppliesToEverySelectedEntry() throws {
    let s = try TestStore()
    let a = try s.store.capture(CaptureInput(term: "alpha", capturedAt: t0, senses: [.tr("а")]))
    let b = try s.store.capture(CaptureInput(term: "beta", capturedAt: t0, senses: [.tr("б")]))
    let c = try s.store.capture(CaptureInput(term: "gamma", capturedAt: t0, senses: [.tr("г")]))
    func stages() throws -> [ToriID: WordStage] {
        Dictionary(uniqueKeysWithValues: try s.store.read { try $0.words(WordsQuery()) }.map { ($0.id, $0.stage) })
    }
    try s.store.setStatus([a, b], .paused)
    #expect(try stages() == [a: .paused, b: .paused, c: .new])
    try s.store.setStatus([a, b, c], .known)
    #expect(try stages() == [a: .known, b: .known, c: .known])
    try s.store.setStatus([a, c], .active)
    #expect(try stages() == [a: .new, b: .known, c: .new])
}

@Test func bulkTagOnlyAddsAndKeepsExistingTags() throws {
    let s = try TestStore()
    let a = try s.store.capture(CaptureInput(term: "alpha", capturedAt: t0, tags: ["Home", "reading"]))
    let b = try s.store.capture(CaptureInput(term: "beta", capturedAt: t0))
    try s.store.tag([a, b], names: ["home", "Work"])
    func tags(_ e: ToriID) throws -> [String] { try #require(try s.store.read { try $0.entry(e) }).tags.map(\.name).sorted() }
    #expect(try tags(a) == ["Home", "Work", "reading"])
    #expect(try tags(b) == ["Home", "Work"])
    #expect(try s.store.read { try $0.allTags() }.count == 3)
}

@Test func bulkDeleteRemovesOnlyTheSelection() throws {
    let s = try TestStore()
    let a = try s.store.capture(CaptureInput(term: "alpha", capturedAt: t0))
    let b = try s.store.capture(CaptureInput(term: "beta", capturedAt: t0))
    let c = try s.store.capture(CaptureInput(term: "gamma", capturedAt: t0))
    try s.store.deleteEntries([a, c])
    #expect(try s.store.read { try $0.words(WordsQuery()) }.map(\.id) == [b])
    #expect(try s.store.read { try $0.entry(a) } == nil)
}
