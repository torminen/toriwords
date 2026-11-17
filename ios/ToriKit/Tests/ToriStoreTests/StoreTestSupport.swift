import Foundation
import GRDB
import ToriCore
@testable import ToriStore

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64
    init(_ ms: Int64) { value = ms }
    var ms: Int64 {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    func advance(days: Int) { ms += Int64(days) * 86_400_000 }
}

/// 2025-11-10 12:00 UTC.
let t0: Int64 = 1_762_776_000_000

struct TestStore {
    let store: ToriStore
    let clock: TestClock
    let dir: URL

    init(now: Int64 = t0, launch: Bool = true) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let clock = TestClock(now)
        self.clock = clock
        store = try ToriStore(path: dir.appendingPathComponent("user.sqlite").path, now: { clock.ms })
        if launch { try store.launch(deviceMarker: marker, displayName: "iPhone", purgeKeychain: {}) }
    }

    var marker: URL { dir.appendingPathComponent("device-marker") }

    func signIn(_ account: String = "acc-1") throws { try store.setSyncState([.accountId: account]) }

    func scalar<T: DatabaseValueConvertible>(_ sql: String, _ args: StatementArguments = []) throws -> T? {
        try store.db.read { try T.fetchOne($0, sql: sql, arguments: args) }
    }

    func rows(_ sql: String, _ args: StatementArguments = []) throws -> [Row] {
        try store.db.read { try Row.fetchAll($0, sql: sql, arguments: args) }
    }

    /// Records of this store as another device would pull them.
    func records() throws -> [SyncRecord] {
        try JSONDecoder().decode(Backup.self, from: store.exportBackup(attribution: "")).records
    }

    /// Logical content for equality checks: synced state, derived columns and card caches; IDs as strings.
    func dump() throws -> [String] {
        var out: [String] = []
        for type in RecordType.all where type != .device {
            for row in try rows("SELECT * FROM \(type.name) ORDER BY id") {
                let cols = row.columnNames.sorted().filter { $0 != "is_this_device" }
                out.append(type.name + " " + cols.map { "\($0)=\(row[$0] as DatabaseValue)" }.joined(separator: " "))
            }
        }
        return out
    }
}

extension NewSense {
    static func tr(_ t: String) -> NewSense { NewSense(translation: t, source: .wiktionary, dictVersion: "2026.11.1") }
}
