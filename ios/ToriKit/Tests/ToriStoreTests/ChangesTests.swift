import Foundation
import Testing
import ToriCore
@testable import ToriStore

@Test func captureEmitsVocabularyChangeAndOutboxGrowsOnlyWhenSyncing() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try ToriStore(path: dir.appendingPathComponent("user.sqlite").path, now: { 1_762_776_000_000 })
    try store.launch(deviceMarker: dir.appendingPathComponent("marker"), displayName: "A")
    var events = store.vocabularyChanges().makeAsyncIterator()
    _ = try store.capture(CaptureInput(term: "run", capturedAt: 1_762_776_000_000, senses: [], sentence: nil, source: nil, tags: []))
    let event: Void? = await events.next()
    #expect(event != nil)
    #expect(try store.read { try $0.pendingChangeCount() } == 0, "local-only: no outbox rows")
    try store.activateCloud(user: "user-1")
    #expect(try store.read { try $0.pendingChangeCount() } > 0)
}
