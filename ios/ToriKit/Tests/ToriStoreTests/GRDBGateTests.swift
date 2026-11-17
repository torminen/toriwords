import Foundation
import GRDB
import Testing

/// Gate: the GRDB features ToriStore relies on work on every platform the suite runs on.
@Test func migrationPoolWriteAndObservation() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pool = try DatabasePool(path: dir.appendingPathComponent("user.sqlite").path)
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
        try db.create(table: "entry") { t in
            t.primaryKey("id", .text)
            t.column("text", .text).notNull()
        }
    }
    try migrator.migrate(pool)
    #expect(try await pool.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")

    let counts = ValueObservation
        .tracking { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entry") ?? 0 }
        .removeDuplicates()  // a pool may re-notify an unchanged value when tracking starts
        .values(in: pool)
    var iterator = counts.makeAsyncIterator()
    #expect(try await iterator.next() == 0)

    try await pool.write { try $0.execute(sql: "INSERT INTO entry (id, text) VALUES ('a', 'run')") }
    #expect(try await iterator.next() == 1)
}
