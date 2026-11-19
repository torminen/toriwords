import Foundation
import GRDB
import ToriCore

public enum LaunchOutcome: Equatable, Sendable {
    case existing, freshInstall, restoredFromBackup
}

extension ToriStore {
    /// Launch: fresh install or restored-from-backup handling, after the migration in `init`. `deviceMarker` lives in Application Support and is excluded from
    /// backup; `purgeKeychain` deletes Session tokens left by a previous installation (fresh install only).
    @discardableResult
    public func launch(deviceMarker: URL, displayName: String, purgeKeychain: () -> Void) throws -> LaunchOutcome {
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
                // Restored: tokens were not restored, so this install is signed out; `lastSyncedAccountId` stays.
                try Account.signedOutState(tx.db)
                return .restoredFromBackup
            }
            try Defaults.create(tx)
            return .freshInstall
        }
        try writeMarker(deviceMarker)
        if outcome == .freshInstall { purgeKeychain() }
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

    /// Account prompt "Remove from this device" (stays signed in): one transaction deleting every synced user record, re-creating
    /// the LanguagePair and Settings defaults, deleting the outbox, resetting `cursor` and clearing `pendingAccountChoice`.
    public func removeAllUserRecords() throws {
        try write { tx in
            try Account.deleteUserRecords(tx)
            try SyncStateStore.set(tx.db, .cursor, nil)
            try SyncStateStore.set(tx.db, .pendingAccountChoice, nil)
        }
    }

    /// Settings → Data → "Remove all data from this device": deletes all user records, recreates defaults and
    /// signs out (auth keys of `sync_state` cleared; `signOut` deletes the Keychain tokens after commit).
    public func removeAllDataFromDevice(signOut: () -> Void) throws {
        try write { tx in
            try Account.deleteUserRecords(tx)
            try Account.signedOutState(tx.db)
        }
        signOut()
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
    }

    /// Sign-out state: session keys, cursor and outbox gone; data and `lastSyncedAccountId` kept.
    static func signedOutState(_ db: Database) throws {
        for key in [SyncStateKey.accountId, .cursor, .adoptedAccountId, .pendingAccountChoice] { try SyncStateStore.set(db, key, nil) }
        try db.execute(sql: "DELETE FROM pending_changes")
    }
}
