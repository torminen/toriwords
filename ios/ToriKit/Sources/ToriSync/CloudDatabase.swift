import Foundation
import ToriCore

/// iCloud availability for the app; `userID` is the iCloud user record name.
public enum CloudAccount: Equatable, Sendable {
    case available(userID: String)
    case unavailable
}

/// One sync record as stored in the cloud. `meta` = archived system fields (nil: never saved from this device);
/// `modifiedAt` = the cloud modification date, Unix ms (0 when unknown).
public struct CloudRecord: Equatable, Sendable {
    public var envelope: SyncRecord
    public var meta: Data?
    public var modifiedAt: Int64

    public init(envelope: SyncRecord, meta: Data?, modifiedAt: Int64) {
        self.envelope = envelope
        self.meta = meta
        self.modifiedAt = modifiedAt
    }
}

/// One page of zone changes after `token`.
public struct CloudChanges: Sendable {
    public var records: [CloudRecord]
    public var deletedIDs: [ToriID]
    /// The `zone-info` marker's generation when it is part of this page.
    public var zoneGeneration: String?
    /// Opaque (archived `CKServerChangeToken`).
    public var token: Data
    public var moreComing: Bool

    public init(records: [CloudRecord], deletedIDs: [ToriID], zoneGeneration: String?, token: Data, moreComing: Bool) {
        self.records = records
        self.deletedIDs = deletedIDs
        self.zoneGeneration = zoneGeneration
        self.token = token
        self.moreComing = moreComing
    }
}

/// Per-record result of a non-atomic save.
public enum SaveOutcome: Equatable, Sendable {
    case saved(meta: Data, modifiedAt: Int64)
    /// `serverRecordChanged` (stale tag, or a record that already exists while this device has no meta): the server copy.
    case conflict(CloudRecord)
    /// The stored system fields point to a record the cloud no longer has.
    case unknownItem
    /// Not attempted (`batchRequestFailed` in a partial failure): send again.
    case retry
    case failed(CloudError)
}

public enum CloudError: Error, Equatable, Sendable {
    /// `networkUnavailable` / `networkFailure`.
    case network
    /// `requestRateLimited` / `zoneBusy` / `serviceUnavailable`, seconds.
    case rateLimited(retryAfter: Int)
    case quotaExceeded
    case notAuthenticated
    /// `userDeletedZone`: deleted in iOS Settings.
    case zoneDeleted
    /// `zoneNotFound`: deleted by the app on another device (or not created yet).
    case zoneNotFound
    case changeTokenExpired
    /// The request was too large: send fewer records.
    case limitExceeded
    case unknownItem
    case other(String)
}

/// The cloud store: the private database of one iCloud user, one custom zone. CloudKit in the app, memory in tests.
public protocol CloudDatabase: Sendable {
    func accountStatus() async throws -> CloudAccount
    /// Creates the zone if absent (idempotent).
    func ensureZone() async throws
    /// Saves a fresh `zone-info` marker with `generation` unless one exists; returns the generation the cloud holds.
    func claimZoneGeneration(_ generation: String) async throws -> String
    /// `token` nil = from the start. Throws `zoneNotFound`/`zoneDeleted` when the zone is gone, `changeTokenExpired`.
    func fetchChanges(token: Data?) async throws -> CloudChanges
    /// Non-atomic save with "if server record unchanged"; a missing `meta` saves a fresh record.
    func save(_ records: [CloudRecord]) async throws -> [ToriID: SaveOutcome]
    func delete(_ ids: [ToriID]) async throws
    func deleteZone() async throws
}
