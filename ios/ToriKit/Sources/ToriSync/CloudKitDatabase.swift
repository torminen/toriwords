#if canImport(CloudKit)
import CloudKit
import Foundation
import ToriCore

/// `CloudDatabase` over the iCloud private database: custom zone `Toriwords`, one `Record` per sync record (the full
/// envelope as JSON), the `zone-info` marker (`ZoneInfo.generation`). CloudKit never merges; the engine does.
public final class CloudKitDatabase: CloudDatabase, @unchecked Sendable {
    static var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: "Toriwords", ownerName: CKCurrentUserDefaultName) }
    static var infoID: CKRecord.ID { CKRecord.ID(recordName: "zone-info", zoneID: zoneID) }
    static let recordType = "Record"

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    /// `container`: e.g. `iCloud.com.toriwords.app`.
    public init(container: String) {
        self.container = CKContainer(identifier: container)
    }

    public func accountStatus() async throws -> CloudAccount {
        do {
            guard try await container.accountStatus() == .available else { return .unavailable }
            return .available(userID: try await container.userRecordID().recordName)
        } catch {
            throw Self.map(error)
        }
    }

    public func ensureZone() async throws {
        try await mapped {
            let (saved, _) = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
            for result in saved.values { _ = try result.get() }
        }
    }

    public func claimZoneGeneration(_ generation: String) async throws -> String {
        try await mapped {
            let marker = CKRecord(recordType: "ZoneInfo", recordID: Self.infoID)
            marker["generation"] = generation
            let (saved, _) = try await database.modifyRecords(saving: [marker], deleting: [], savePolicy: .ifServerRecordUnchanged,
                                                              atomically: false)
            switch saved[Self.infoID] {
            case .success(let record)?:
                return record["generation"] as? String ?? generation
            case .failure(let error)?:
                // Another device claimed first: adopt its generation.
                if let ck = error as? CKError, ck.code == .serverRecordChanged, let value = ck.serverRecord?["generation"] as? String {
                    return value
                }
                throw error
            case nil:
                return generation
            }
        }
    }

    public func fetchChanges(token: Data?) async throws -> CloudChanges {
        try await mapped {
            let since = try token.flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
            let changes = try await database.recordZoneChanges(inZoneWith: Self.zoneID, since: since)
            var out = CloudChanges(records: [], deletedIDs: [], zoneGeneration: nil,
                                   token: try NSKeyedArchiver.archivedData(withRootObject: changes.changeToken, requiringSecureCoding: true),
                                   moreComing: changes.moreComing)
            for (id, result) in changes.modificationResultsByID {
                let record = try result.get().record
                if id == Self.infoID {
                    out.zoneGeneration = record["generation"] as? String
                } else if let cloud = Self.cloudRecord(record) {
                    out.records.append(cloud)
                }
            }
            out.deletedIDs = changes.deletions.compactMap { ToriID($0.recordID.recordName) }
            return out
        }
    }

    public func save(_ records: [CloudRecord]) async throws -> [ToriID: SaveOutcome] {
        try await mapped {
            let ckRecords = try records.map(Self.ckRecord)
            let (saved, _) = try await database.modifyRecords(saving: ckRecords, deleting: [], savePolicy: .ifServerRecordUnchanged,
                                                              atomically: false)
            var out: [ToriID: SaveOutcome] = [:]
            for r in records {
                switch saved[Self.recordID(r.envelope.id)] {
                case .success(let record)?:
                    out[r.envelope.id] = .saved(meta: Self.systemFields(record), modifiedAt: Self.ms(record.modificationDate))
                case .failure(let error)?:
                    out[r.envelope.id] = Self.outcome(error)
                case nil:
                    out[r.envelope.id] = .retry
                }
            }
            return out
        }
    }

    public func delete(_ ids: [ToriID]) async throws {
        guard !ids.isEmpty else { return }
        try await mapped {
            let (_, deleted) = try await database.modifyRecords(saving: [], deleting: ids.map(Self.recordID), atomically: false)
            for result in deleted.values {
                do { try result.get() } catch let ck as CKError where ck.code == .unknownItem {}  // already gone
            }
        }
    }

    public func deleteZone() async throws {
        try await mapped {
            let (_, deleted) = try await database.modifyRecordZones(saving: [], deleting: [Self.zoneID])
            for result in deleted.values { try result.get() }
        }
    }

    // MARK: Mapping

    private func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw Self.map(error) }
    }

    static func recordID(_ id: ToriID) -> CKRecord.ID { CKRecord.ID(recordName: id.description, zoneID: zoneID) }

    static func ckRecord(_ r: CloudRecord) throws -> CKRecord {
        let record = r.meta.flatMap(decodeSystemFields) ?? CKRecord(recordType: recordType, recordID: recordID(r.envelope.id))
        record["type"] = r.envelope.type
        record["schema"] = r.envelope.schema
        record["owner"] = r.envelope.owner?.description
        record["envelope"] = try JSONEncoder().encode(r.envelope)
        return record
    }

    /// nil for anything that is not a readable sync record.
    static func cloudRecord(_ record: CKRecord) -> CloudRecord? {
        guard record.recordType == recordType, let data = record["envelope"] as? Data,
              let envelope = try? JSONDecoder().decode(SyncRecord.self, from: data) else { return nil }
        return CloudRecord(envelope: envelope, meta: systemFields(record), modifiedAt: ms(record.modificationDate))
    }

    static func systemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    static func ms(_ date: Date?) -> Int64 { date.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0 }

    /// Per-record save failure.
    static func outcome(_ error: Error) -> SaveOutcome {
        guard let ck = error as? CKError else { return .failed(map(error)) }
        switch ck.code {
        case .serverRecordChanged:
            return ck.serverRecord.flatMap(cloudRecord).map(SaveOutcome.conflict) ?? .retry
        case .unknownItem:
            return .unknownItem
        case .batchRequestFailed:
            return .retry
        default:
            return .failed(map(ck))
        }
    }

    static func map(_ error: Error) -> CloudError {
        if let e = error as? CloudError { return e }
        guard let ck = error as? CKError else { return .other(String(describing: error)) }
        switch ck.code {
        case .networkUnavailable, .networkFailure:
            return .network
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .rateLimited(retryAfter: Int(ck.retryAfterSeconds ?? 30))
        case .quotaExceeded:
            return .quotaExceeded
        case .notAuthenticated:
            return .notAuthenticated
        case .userDeletedZone:
            return .zoneDeleted
        case .zoneNotFound:
            return .zoneNotFound
        case .changeTokenExpired:
            return .changeTokenExpired
        case .limitExceeded:
            return .limitExceeded
        case .unknownItem:
            return .unknownItem
        case .partialFailure:
            // The item error that names the cause (zone gone, quota…), not the "not attempted" ones.
            let inner = (ck.partialErrorsByItemID ?? [:]).values.compactMap { $0 as? CKError }
            return (inner.first { $0.code != .batchRequestFailed } ?? inner.first).map { Self.map($0) } ?? .other("partialFailure")
        default:
            return .other("CKError \(ck.code.rawValue)")
        }
    }
}
#endif
