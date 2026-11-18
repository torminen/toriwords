import Foundation
import GRDB
import Testing
import ToriCore
import ToriTestSupport
@testable import ToriDictionary

/// `<repo>/ios/Resources/<name>`.
func resource(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/\(name)")
}

let sample = try! BundledDictionary(path: resource("dictionary-sample.sqlite").path)

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A minimal dictionary file with the §8.2 tables the queries touch.
func makeDictionary(at url: URL, version: String, keys: [String] = []) throws {
    let q = try DatabaseQueue(path: url.path)
    try q.write { db in
        try db.execute(sql: """
            CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
            CREATE TABLE headword (id INTEGER PRIMARY KEY, text TEXT NOT NULL, key TEXT NOT NULL, pos TEXT NOT NULL,
              freq_rank INTEGER, ipa TEXT, is_phrase INTEGER NOT NULL);
            CREATE INDEX headword_key ON headword(key);
            CREATE TABLE translation_ru (id INTEGER PRIMARY KEY, headword_id INTEGER NOT NULL, sense_id INTEGER,
              text TEXT NOT NULL, text_folded TEXT NOT NULL, origin TEXT NOT NULL, rank INTEGER NOT NULL);
            """)
        try db.execute(sql: "INSERT INTO meta VALUES ('dictionary_version', ?)", arguments: [version])
        for (i, k) in keys.enumerated() {
            try db.execute(sql: "INSERT INTO headword VALUES (?, ?, ?, 'noun', NULL, NULL, 0)", arguments: [i + 1, k, k])
        }
    }
    try q.close()
}

@Test func metaVersionAndLicence() throws {
    #expect(sample.version.hasSuffix("-sample"))
    #expect(sample.licenceText.contains("CC BY-SA 4.0"))
    let meta = try sample.meta()
    #expect(meta["dictionary_version"] == sample.version && meta["enwikt_sha256"]?.count == 64)
}

@Test func autocompleteOrderPrimaryTranslationAndExclusion() throws {
    let rows = try sample.autocomplete(prefix: "lo")
    #expect(rows.count == 8)
    let ranks = rows.map { $0.freqRank ?? .max }
    #expect(ranks == ranks.sorted())
    #expect(rows.allSatisfy { $0.key.hasPrefix("lo") })
    #expect(rows.first?.key == "love")  // freq_rank 150 is the smallest under "lo" in the sample
    let look = try #require(try sample.autocomplete(prefix: "look").first { $0.key == "look" && $0.partOfSpeech == "verb" })
    #expect(look.primaryTranslation != nil && !look.isPhrase)
    let phrases = try sample.autocomplete(prefix: "look a")
    #expect(phrases.map(\.text) == ["look after"] && phrases[0].isPhrase)
    #expect(try sample.autocomplete(prefix: "lo", excluding: ["look"]).allSatisfy { $0.key != "look" })
    #expect(try sample.autocomplete(prefix: "").isEmpty)
}

@Test(arguments: Fixture.cases("normalization/text-order.json").filter { $0.json.has("prefix") })
func textOrderThroughAutocompleteRange(_ c: FixtureCase) throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("d.sqlite")
    try makeDictionary(at: url, version: "t", keys: c["keys"].array.map { $0.string! })
    let got = try BundledDictionary(path: url.path).autocomplete(prefix: c["prefix"].string!, limit: 100).map(\.key)
    #expect(got.count == c["expected"].array.count)
    #expect(zip(got, c["expected"].array).allSatisfy { sameScalars($0, $1.string) })
}

@Test func lookupSensesAndRankedVariants() throws {
    let hws = try sample.headwords(key: "look after")
    let hw = try #require(hws.first)
    #expect(hw.isPhrase && !hw.senses.isEmpty)
    #expect(hw.translations.map(\.rank) == Array(1...hw.translations.count))
    #expect(hw.translations.first?.senseOrdinal != nil)
    #expect(hw.translations.contains { $0.senseOrdinal == nil && $0.origin == .ruwikt })
    let run = try sample.headwords(key: "run")
    #expect(Set(run.map(\.partOfSpeech)) == ["adj", "noun", "verb"])
    #expect(run.first { $0.partOfSpeech == "verb" }?.senses.map(\.ordinal) == Array(1...run.first { $0.partOfSpeech == "verb" }!.senses.count))
    #expect(try sample.headwords(key: "qwertyuiop").isEmpty)
}

@Test func baseFormOfferOnlyWithoutExactHitAndNeverForPhrases() throws {
    let ran = try sample.resolve("Ran")
    #expect(ran.headwords.isEmpty)
    #expect(ran.baseForms.map { "\($0.headword.text)/\($0.headword.partOfSpeech)/\($0.formTags ?? "")" } == ["run/verb/past"])
    let houses = try sample.baseForms(of: "houses").map(\.headword.partOfSpeech)
    #expect(houses == ["noun", "verb"])
    #expect(try sample.resolve("run").baseForms.isEmpty)
    #expect(try sample.resolve("ran away").baseForms.isEmpty)
}

@Test func containedPhrasesThroughBaseForms() throws {
    let found = try sample.containedPhrases(in: "She looked after her brother and looked for him.")
    #expect(found.map(\.text) == ["look after", "look for"])
    #expect(try sample.resolve("I was looking forward to it").containedPhrases.map(\.text) == ["look forward to"])
    // The text's own key is a lookup hit, not a contained phrase.
    #expect(try sample.containedPhrases(in: "look after").isEmpty)
    #expect(try sample.containedPhrases(in: "look").isEmpty)
}

@Test func reverseLookupOnFoldedRussianPrefix() throws {
    let hits = try sample.reverse("Дом")
    #expect(hits.contains { $0.headword.key == "house" })
    #expect(Set(hits.map(\.headword.id)).count == hits.count)
    #expect(hits.allSatisfy { $0.matchedTranslation.lowercased().contains("дом") })
    #expect(try sample.reverse("ДОМ") == hits)
    #expect(try sample.reverse("дом house").isEmpty)  // Latin letters → not a Russian query
    #expect(try sample.reverse("123").isEmpty)
    #expect(try sample.reverse("\"дом").map(\.headword.id) == hits.map(\.headword.id))  // quotes escaped
    #expect(BundledDictionary.isRussianInput("ёж") && !BundledDictionary.isRussianInput("ёж é"))
}

@Test func relatedOrderedByKindThenFrequency() throws {
    let look = try #require(try sample.headwords(key: "look").first { $0.partOfSpeech == "intj" })
    #expect(try sample.related(to: look.id).map(\.headword.text) == ["so", "see", "well"])
    let verb = try #require(try sample.headwords(key: "look").first { $0.partOfSpeech == "verb" })
    let related = try sample.related(to: verb.id)
    #expect(related.count <= 8 && related.allSatisfy { $0.kind == .phrase })
    #expect(try sample.related(to: -1).isEmpty)
}

@Test func relatedIsEmptyWhenTheBuildPrunedIt() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("d.sqlite")
    try FileManager.default.copyItem(at: resource("dictionary-sample.sqlite"), to: url)
    let q = try DatabaseQueue(path: url.path)
    try q.write { try $0.execute(sql: "DELETE FROM related") }
    try q.close()
    #expect(try BundledDictionary(path: url.path).related(to: 1).isEmpty)
}

@Test func missingVersionIsAnError() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("d.sqlite")
    try makeDictionary(at: url, version: "x")
    let q = try DatabaseQueue(path: url.path)
    try q.write { try $0.execute(sql: "DELETE FROM meta") }
    try q.close()
    #expect(throws: DictionaryError.missingVersion(url.path)) { try BundledDictionary(path: url.path) }
}

// MARK: Full dictionary (skipped unless ios/Resources/dictionary.sqlite exists)

let fullDictionary = resource("dictionary.sqlite")

@Test(.enabled(if: FileManager.default.fileExists(atPath: fullDictionary.path)))
func autocompleteOnFullDictionaryUnder10ms() throws {
    let dict = try BundledDictionary(path: fullDictionary.path)
    _ = try dict.autocomplete(prefix: "warmup")
    var worst = 0.0
    for p in ["a", "co", "re", "st", "pr", "th", "in", "ma", "un", "de", "take o", "run", "zz", "qu", "ко"] {
        var best = Double.infinity  // per keystroke after the first page reads; worst prefix decides
        for _ in 0..<3 {
            let start = Date()
            _ = try dict.autocomplete(prefix: p)
            best = min(best, Date().timeIntervalSince(start) * 1000)
        }
        worst = max(worst, best)
    }
    print("autocomplete worst on full dictionary: \(String(format: "%.2f", worst)) ms")
    #expect(worst < 10)
}

/// Prints the other §16.2-relevant timings on the full file (no assertion beyond sanity; budgets are per-screen).
@Test(.enabled(if: FileManager.default.fileExists(atPath: fullDictionary.path)))
func otherTimingsOnFullDictionary() throws {
    let dict = try BundledDictionary(path: fullDictionary.path)
    func ms(_ body: () throws -> Void) rethrows -> String {
        let start = Date()
        try body()
        return String(format: "%.2f", Date().timeIntervalSince(start) * 1000)
    }
    let lookup = try ms { _ = try dict.resolve("run") }
    let base = try ms { _ = try dict.resolve("ran") }
    var found: [Completion] = [], hits: [ReverseHit] = []
    let phrases = try ms { found = try dict.containedPhrases(in: "The plane took off late and we ran out of time.") }
    let reverse = try ms { hits = try dict.reverse("соба") }
    #expect(found.map(\.key).contains("take off") && !hits.isEmpty)
    let reverseShort = try ms { _ = try dict.reverse("д") }
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let install = try ms { _ = try DictionaryInstaller(bundled: fullDictionary, installed: dir.appendingPathComponent("d.sqlite")).installIfNeeded() }
    print("full dictionary ms: resolve(run) \(lookup), resolve(ran) \(base), containedPhrases \(phrases), reverse(соба) \(reverse), reverse(д) \(reverseShort), install \(install)")
}

@Test func variantsKeepHeadwordAndRankOrderWithoutRepeats() throws {
    let hws = try sample.headwords(key: "run")
    let variants = Variant.of(hws)
    let expected = hws.flatMap { $0.translations.map(\.text) }
    #expect(variants.count == Set(expected.map { TextKey.translationKey($0) }).count)
    #expect(variants.first?.translation == expected.first)
    #expect(variants.allSatisfy { v in v.senseOrdinal == nil ? v.glossEn == nil : v.glossEn != nil })
    #expect(Variant.of([]).isEmpty)
}
