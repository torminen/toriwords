import Foundation
import Testing
import ToriCore
@testable import ToriShared

private func tempGroup() throws -> AppGroup {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return AppGroup(root: dir)
}

private func canonical(_ json: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(json.utf8)), options: [.sortedKeys])
}

private func roundTrips<T: Codable & Equatable>(_ type: T.Type, _ json: String) throws -> T {
    let value = try JSONDecoder().decode(T.self, from: Data(json.utf8))
    let reencoded = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(T.self, from: reencoded) == value)
    return value
}

/// Doc 36 §5.3.1 example (placeholders filled in).
@Test func inboxFileDocExample() throws {
    let json = """
    { "format": 1, "captureId": "0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01", "capturedAt": 1762790400000, "utcOffsetMin": 180,
      "languagePair": { "native": "ru", "target": "en" }, "term": "take off",
      "sentence": "The plane took off an hour late.", "highlight": { "offset": 10, "length": 8 },
      "source": { "url": "https://example.com/a", "title": "News" }, "tags": ["work"],
      "chosenSenses": [ { "translation": "взлетать", "definition": "To leave the ground", "pos": "verb",
        "provenance": { "kind": "wiktionary", "dictVersion": "2026.11.1", "headwordKey": "take off", "senseOrdinal": 0 } } ],
      "typedTranslation": null, "origin": "shared" }
    """
    let file = try roundTrips(InboxFile.self, json)
    #expect(file.captureId == ToriID("0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01"))
    #expect(file.highlight == Capture.Highlight(offset: 10, length: 8))
    #expect(file.chosenSenses.first?.provenance.senseOrdinal == 0)
    #expect(file.resume == false)  // absent → default
    #expect(file.typedTranslation == nil)

    let minimal = try roundTrips(InboxFile.self, """
    { "format": 1, "captureId": "0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01", "capturedAt": 1, "utcOffsetMin": 0,
      "languagePair": { "native": "ru", "target": "en" }, "term": "x", "chosenSenses": [], "origin": "shared", "resume": true }
    """)
    #expect(minimal.sentence == nil && minimal.source == nil && minimal.tags == nil && minimal.resume)
}

@Test func vocabIndexAndStickyDocExamples() throws {
    let index = try roundTrips(VocabIndex.self, """
    { "format": 1, "generatedAt": 1762790400000,
      "entries": [ ["mortgage", "0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01", ["ипотека"], "active"] ],
      "tags": [ ["work", "Work"] ] }
    """)
    #expect(index.entries[0].translations == ["ипотека"] && index.entries[0].status == .active)
    #expect(index.tags == [VocabIndex.Tag(key: "work", name: "Work")])
    #expect(index.entry(matching: "  Mortgage ")?.matchKey == "mortgage")
    // Arrays stay arrays on the wire.
    #expect(try canonical(String(decoding: JSONEncoder().encode(index), as: UTF8.self)) == canonical("""
    {"format":1,"generatedAt":1762790400000,"entries":[["mortgage","0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01",["ипотека"],"active"]],"tags":[["work","Work"]]}
    """))

    let sticky = try roundTrips(CaptureSticky.self,
        #"{ "format": 1, "updatedAt": 1000, "sourceTitle": "The Bear S2E3", "tags": ["work"], "tipShown": true }"#)
    #expect(sticky.offered(now: 1000 + CaptureSticky.offerWindowMs).sourceTitle == "The Bear S2E3")
    #expect(sticky.offered(now: 1001 + CaptureSticky.offerWindowMs).tags.isEmpty)
    _ = try roundTrips(CaptureSticky.self, #"{ "format": 1, "updatedAt": 1, "sourceTitle": null, "tags": [], "tipShown": false }"#)
}

@Test func widgetSnapshotDocExample() throws {
    let group = try tempGroup()
    defer { try? FileManager.default.removeItem(at: group.root) }
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data("""
    { "format": 1, "generatedAt": 1762790400000, "utcOffsetMin": 180,
      "days": [ { "day": 20402, "dueReviews": 12, "newAvailable": 5 }, { "day": 20403, "dueReviews": 19, "newAvailable": 10 } ],
      "nextDueDay": 20402, "homeState": "due" }
    """.utf8))
    try group.writeWidgetSnapshot(snapshot)
    #expect(try group.readWidgetSnapshot() == snapshot)
}

@Test func atomicWriteReplacesAndLeavesNoTemp() throws {
    let group = try tempGroup()
    defer { try? FileManager.default.removeItem(at: group.root) }
    #expect(try group.readCaptureSticky() == nil)
    try group.writeCaptureSticky(CaptureSticky(updatedAt: 1, sourceTitle: "a", tags: [], tipShown: false))
    try group.writeCaptureSticky(CaptureSticky(updatedAt: 2, sourceTitle: nil, tags: ["t"], tipShown: true))
    #expect(try group.readCaptureSticky()?.updatedAt == 2)
    #expect(try FileManager.default.contentsOfDirectory(atPath: group.root.path) == ["capture-sticky.json"])
}

@Test func inboxListsInCaptureIdOrderAndIgnoresTempFiles() throws {
    let group = try tempGroup()
    defer { try? FileManager.default.removeItem(at: group.root) }
    let inbox = group.inbox
    #expect(inbox.pending().isEmpty)  // directory not created yet
    let ids = [3, 1, 2].map { ToriID.v7(unixMs: Int64($0) * 1000, randA: 0, randB: 0) }
    for id in ids { try inbox.write(InboxFile(captureId: id, capturedAt: 0, utcOffsetMin: 0, term: "w\(id)")) }
    try Data("{}".utf8).write(to: inbox.directory.appendingPathComponent(".tmp-\(ids[0]).json"))
    try Data("{}".utf8).write(to: inbox.directory.appendingPathComponent("notes.json"))
    #expect(inbox.pending() == ids.sorted())

    guard case .capture(let file) = try inbox.read(ids[1]) else { Issue.record("not a capture"); return }
    #expect(file.term == "w\(ids[1])")

    try Data(#"{"format": 2, "anything": true}"#.utf8).write(to: inbox.url(for: ids[2]))
    guard case .unknownFormat(2) = try inbox.read(ids[2]) else { Issue.record("expected unknown format"); return }

    try inbox.delete(ids[1])
    try inbox.delete(ids[1])  // idempotent
    #expect(inbox.pending() == [ids[0], ids[2]].sorted())
}

// MARK: Deep links

@Test(arguments: [
    ("toriwords://review", DeepLink.review),
    ("TORIWORDS://Review", .review),
    ("toriwords:review", .review),
    ("toriwords://add", .add(text: nil)),
    ("toriwords://add?text=", .add(text: nil)),
    ("toriwords://add?text=%20take%20off%0A", .add(text: "take off")),
    ("toriwords://add?text=%D0%B2%D0%B7%D0%BB%D0%B5%D1%82", .add(text: "взлет")),
])
func deepLinkParses(_ url: String, _ expected: DeepLink) throws {
    #expect(DeepLink(url: try #require(URL(string: url))) == expected)
}

@Test(arguments: ["https://review", "toriwords://progress", "toriwords://", "other://add?text=x"])
func deepLinkRejects(_ url: String) throws {
    #expect(DeepLink(url: try #require(URL(string: url))) == nil)
}

@Test func deepLinkRoundTripsAndCapsText() throws {
    for link in [DeepLink.review, .add(text: nil), .add(text: "a & b = c?")] {
        #expect(DeepLink(url: link.url) == link)
    }
    #expect(DeepLink.review.url.absoluteString == "toriwords://review")
    let long = String(repeating: "я", count: 6000)
    guard case .add(let text?) = DeepLink(url: DeepLink.add(text: long).url) else { Issue.record("no text"); return }
    #expect(text.unicodeScalars.count == 5000)
}
