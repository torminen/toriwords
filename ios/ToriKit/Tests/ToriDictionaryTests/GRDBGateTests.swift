import Foundation
import GRDB
import Testing

/// Gate: FTS5 and an immutable read-only open of a prebuilt dictionary file.
@Test func fts5MatchOnImmutableReadOnlyFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("dictionary.sqlite").path

    let builder = try DatabaseQueue(path: path)
    try builder.write { db in
        try db.execute(sql: """
            CREATE VIRTUAL TABLE ru_fts USING fts5(text_folded, tokenize = "unicode61 remove_diacritics 0");
            INSERT INTO ru_fts (text_folded) VALUES ('бежать'), ('ехать');
            """)
    }
    try builder.close()

    var config = Configuration()
    config.readonly = true
    // A read-only open of a non-URI path would fail here: no file named "file:…?immutable=1" exists.
    let reader = try DatabaseQueue(path: "file:\(path)?immutable=1", configuration: config)
    let hits = try reader.read {
        try String.fetchAll($0, sql: "SELECT text_folded FROM ru_fts WHERE ru_fts MATCH ?", arguments: ["\"беж\"*"])
    }
    #expect(hits == ["бежать"])
}
