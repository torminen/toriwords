import Foundation
import Testing
import ToriCore
import ToriStore
@testable import ToriEnrichment

// MARK: Fakes

struct FakeDictionary: DictionaryLookup {
    var version = "2026.11.1"
    var entries: [String: [DictionaryHeadword]] = [:]
    func lookup(key: String) throws -> [DictionaryHeadword] { entries[key] ?? [] }
}

final class FakeTranslator: MachineTranslator, @unchecked Sendable {
    private let lock = NSLock()
    private var _ready: Bool
    private var _results: [String: String?]
    private var _calls = 0
    init(ready: Bool = true, results: [String: String?] = [:]) { _ready = ready; _results = results }
    var ready: Bool { get { lock.withLock { _ready } } set { lock.withLock { _ready = newValue } } }
    var calls: Int { lock.withLock { _calls } }
    func isReady() async -> Bool { ready }
    func translate(_ text: String) async throws -> String? {
        try lock.withLock {
            _calls += 1
            guard let r = _results[text] else { throw URLError(.notConnectedToInternet) }
            return r
        }
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1_762_776_000_000
    var ms: Int64 { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
}

let thorough = DictionaryHeadword(text: "thorough", key: "thorough", partOfSpeech: "adjective", ipa: "/ˈθʌr.ə/", senses: [
    DictionarySense(ordinal: 1, glossEn: "Extremely careful.", translationsRu: ["скрупулёзный"]),
    DictionarySense(ordinal: 0, glossEn: "Done with great care.", translationsRu: ["тщательный", "основательный", "Тщательный"]),
])

struct Harness {
    let store: ToriStore
    let clock = Clock()

    init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let clock = self.clock
        store = try ToriStore(path: dir.appendingPathComponent("user.sqlite").path, now: { clock.ms })
        try store.launch(deviceMarker: dir.appendingPathComponent("marker"), displayName: "iPhone", purgeKeychain: {})
    }

    func orchestrator(_ dict: FakeDictionary? = FakeDictionary(), _ mt: FakeTranslator? = nil) -> EnrichmentOrchestrator {
        let clock = self.clock
        return EnrichmentOrchestrator(store: store, dictionary: dict, translator: mt, now: { clock.ms })
    }

    func capture(_ term: String) throws -> ToriID { try store.capture(CaptureInput(term: term, capturedAt: clock.ms)) }
    func entry(_ id: ToriID) throws -> EntryDetail { try #require(try store.read { try $0.entry(id) }) }
}

// MARK: Suggestions

@Test func suggestionsOrderDedupeAndMachineVariant() {
    let s = Suggestions.build(headwords: [thorough], dictVersion: "v", machine: "  основательный ")
    #expect(s.map(\.sense.translation) == ["тщательный", "основательный", "скрупулёзный"])
    #expect(s[0].sense == NewSense(translation: "тщательный", definition: "Done with great care.", partOfSpeech: "adjective",
                                   source: .wiktionary, dictVersion: "v", dictHeadwordKey: "thorough", dictSenseOrdinal: 0))
    // MT equal to a dictionary variant (by translation key, ё→е) is dropped; a new one is appended last.
    #expect(Suggestions.build(headwords: [thorough], dictVersion: "v", machine: "скрупулезный").count == 3)
    let withMT = Suggestions.build(headwords: [thorough], dictVersion: "v", machine: "дотошный")
    #expect(withMT.last?.sense == NewSense(translation: "дотошный", source: .mtApple))
    #expect(withMT.last?.isMachine == true)
    // No hit: MT is the only suggestion.
    #expect(Suggestions.build(headwords: [], dictVersion: "v", machine: "дотошный").map(\.sense.source) == [.mtApple])
}

// MARK: Orchestrator

@Test func dictionaryHitFillsFirstVariantWithProvenance() async throws {
    let h = try Harness()
    let id = try h.capture("Thorough")
    let mt = FakeTranslator(results: ["Thorough": "дотошный"])
    let summary = try await h.orchestrator(FakeDictionary(entries: ["thorough": [thorough]]), mt).runPending()
    #expect(summary.filled == 1)
    #expect(mt.calls == 0)
    let e = try h.entry(id)
    #expect(e.translation == .has("тщательный"))
    #expect(e.needsCheck)
    #expect(e.ipa == "/ˈθʌr.ə/")
    #expect(e.senses.map(\.id) == [ToriID.autoSense(entry: id, ordinal: 0)])
    #expect(e.senses[0].definition == "Done with great care.")
    #expect(try h.store.read { try $0.pendingEnrichment() }.isEmpty)
}

@Test func machineTranslationOnlyWhenNoDictionaryHit() async throws {
    let h = try Harness()
    let id = try h.capture("gobbledygook")
    let summary = try await h.orchestrator(FakeDictionary(), FakeTranslator(results: ["gobbledygook": "тарабарщина"])).runPending()
    #expect(summary.filled == 1)
    let e = try h.entry(id)
    #expect(e.translation == .has("тарабарщина"))
    #expect(e.needsCheck)
    let suggestions = await h.orchestrator(FakeDictionary(), FakeTranslator(results: ["x": "икс"])).suggestions(for: "x")
    #expect(suggestions.map(\.sense.source) == [.mtApple])
}

@Test func mtNotReadyStaysPendingWithoutCountingAttempts() async throws {
    let h = try Harness()
    let id = try h.capture("gobbledygook")
    let mt = FakeTranslator(ready: false)
    let o = h.orchestrator(FakeDictionary(), mt)
    for _ in 0..<5 { #expect(try await o.runPending().deferred == 1) }
    #expect(mt.calls == 0)
    #expect(try h.entry(id).translation == .pending)
}

@Test func threeMTFailuresMakeUnavailableWithBackoff() async throws {
    let h = try Harness()
    let id = try h.capture("gobbledygook")
    let mt = FakeTranslator(results: ["gobbledygook": String?.none])
    let o = h.orchestrator(FakeDictionary(), mt)
    #expect(try await o.runPending().failed == 1)
    // Within the backoff window nothing is attempted.
    #expect(try await o.runPending().deferred == 1)
    #expect(mt.calls == 1)
    h.clock.ms += 60_000
    #expect(try await o.runPending().failed == 1)
    #expect(try h.entry(id).translation == .pending)
    h.clock.ms += 120_000
    #expect(try await o.runPending().failed == 1)
    #expect(try h.entry(id).translation == .notFound)
    #expect(try await o.runPending() == .init())
}

@Test func unavailableRetriedAfterDictionaryUpdate() async throws {
    let h = try Harness()
    let id = try h.capture("thorough")
    let o = h.orchestrator(FakeDictionary(), FakeTranslator())
    for _ in 0..<3 { try await o.runPending(); h.clock.ms += 600_000 }
    #expect(try h.entry(id).translation == .notFound)
    let summary = try await o.updateDictionary(FakeDictionary(version: "2026.12.1", entries: ["thorough": [thorough]]))
    #expect(summary.filled == 1)
    let e = try h.entry(id)
    #expect(e.translation == .has("тщательный"))
    #expect(e.needsCheck)
}

@Test func tryAgainResetsAttempts() async throws {
    let h = try Harness()
    let id = try h.capture("gobbledygook")
    let mt = FakeTranslator()
    let o = h.orchestrator(FakeDictionary(), mt)
    for _ in 0..<3 { try await o.runPending(); h.clock.ms += 600_000 }
    #expect(try h.entry(id).translation == .notFound)
    #expect(try await o.tryAgain(id).failed == 1)
    #expect(try h.entry(id).translation == .pending)
}

@Test func userFieldIsNeverOverwrittenByAFill() async throws {
    let h = try Harness()
    let id = try h.capture("thorough")
    let o = h.orchestrator(FakeDictionary(entries: ["thorough": [thorough]]))
    try await o.runPending()
    let auto = ToriID.autoSense(entry: id, ordinal: 0)
    // The user clears the auto-filled translation: rank 1, empty.
    try h.store.editSense(auto, translation: nil, definition: nil, partOfSpeech: nil)
    try h.store.setEntryIPA(id, "/mine/")
    // A later fill (Try again) writes rank 0 only; rank-1 fields keep the user's values.
    try await o.tryAgain(id)
    let e = try h.entry(id)
    #expect(e.senses.first { $0.id == auto }?.translation == nil)
    #expect(e.senses.first { $0.id == auto }?.translationByUser == true)
    #expect(e.translation == TranslationState.none)
    #expect(e.ipa == "/mine/")
}

// MARK: Voices

@Test func voicePickerPrefersAccentThenQualityThenAnyEnglish() {
    let v = { (id: String, lang: String, q: VoicePicker.Quality) in VoicePicker.Voice(identifier: id, language: lang, quality: q) }
    let voices = [v("us-def", "en-US", .default), v("us-enh", "en-US", .enhanced), v("gb-def", "en-GB", .default),
                  v("au-prem", "en-AU", .premium), v("ru", "ru-RU", .premium)]
    #expect(VoicePicker.pick(.us, among: voices)?.identifier == "us-enh")
    #expect(VoicePicker.pick(.uk, among: voices)?.identifier == "gb-def")
    #expect(VoicePicker.pick(.uk, among: voices.filter { !$0.language.hasPrefix("en-GB") })?.identifier == "au-prem")
    #expect(VoicePicker.pick(.us, among: [v("ru", "ru-RU", .premium)]) == nil)
}
