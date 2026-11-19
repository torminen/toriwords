import Foundation
import GRDB
import ToriCore

public enum LaunchOutcome: Equatable, Sendable {
    case existing, freshInstall, restoredFromBackup
}

extension ToriStore {
    /// Launch: fresh install or restored-from-backup handling, after the migration in `init`. `deviceMarker` lives in
    /// Application Support and is excluded from backup.
    @discardableResult
    public func launch(deviceMarker: URL, displayName: String) throws -> LaunchOutcome {
        let marker = (try? Data(contentsOf: deviceMarker)).flatMap { $0.count == 16 ? ToriID(bytes: $0) : nil }
        let outcome: LaunchOutcome = try write { tx in
            let current = try ToriID.fetchOne(tx.db, sql: "SELECT id FROM device WHERE is_this_device = 1")
            if let current, current == marker { return .existing }
            let device = tx.newID()
            try tx.db.execute(sql: "UPDATE device SET is_this_device = 0")
            try tx.db.execute(sql: "INSERT INTO device (id, is_this_device) VALUES (?, 1)", arguments: [device])
            tx.node = device.high
            try tx.set(.device, device, ["platform": .string("ios"), "display_name": .string(displayName),
                                         "first_seen": .int(tx.now)], rank: .automatic)
            guard current == nil else {
                // Restored from a device backup: token and system fields are an older snapshot than the cloud.
                try Account.restoreReset(tx)
                return .restoredFromBackup
            }
            try Defaults.create(tx)
            return .freshInstall
        }
        try writeMarker(deviceMarker)
        return outcome
    }

    private func writeMarker(_ url: URL) throws {
        let id = try db.read { try ToriID.fetchOne($0, sql: "SELECT id FROM device WHERE is_this_device = 1") }
        guard let id else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(id.bytes).write(to: url, options: .atomic)
        #if canImport(Darwin)
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try u.setResourceValues(values)
        #endif
    }

    /// The Device ID of this installation.
    public func thisDeviceID() throws -> ToriID? {
        try db.read { try ToriID.fetchOne($0, sql: "SELECT id FROM device WHERE is_this_device = 1") }
    }

    /// Settings → Data → "Remove all data from this device": deletes all user records and recreates the defaults. Token
    /// and system fields go too, so the next sync downloads everything the cloud still has.
    public func removeAllDataFromDevice() throws {
        try write { tx in try Account.deleteUserRecords(tx) }
    }
}

enum Defaults {
    static let pair = ToriID.languagePair(native: "ru", target: "en")

    /// LanguagePair and Settings defaults, rank 0, deterministic IDs.
    static func create(_ tx: Tx) throws {
        try tx.set(.languagePair, pair, ["native_lang": .string("ru"), "target_lang": .string("en"), "created_at": .int(tx.now)],
                   rank: .automatic)
        let p = FSRSParameters.default
        try tx.set(.settings, .settings, [
            "new_words_per_day": .int(10), "desired_retention": .double(p.desiredRetention),
            "fsrs_w": .array(p.w.map(WireValue.double)), "params_id": .string("fsrs6-default-1"), "scheduler_version": .int(1),
        ], rank: .automatic)
    }
}

enum Account {
    static func deleteUserRecords(_ tx: Tx) throws {
        for type in RecordType.all where type != .device {
            try tx.db.execute(sql: "DELETE FROM \(type.name)")
        }
        try Defaults.create(tx)
        try tx.db.execute(sql: "DELETE FROM pending_changes")
        try CloudMeta.reset(tx.db)
    }

    /// Restored install: token and system fields cleared, every record pending; `cloudDeleted` untouched.
    static func restoreReset(_ tx: Tx) throws {
        try CloudMeta.reset(tx.db)
        try Outbox.markAll(tx)
    }
}
