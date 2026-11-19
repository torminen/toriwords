import Foundation
import ToriCore
@testable import ToriStore
@testable import ToriSync

/// In-memory iCloud private database for tests: one zone per iCloud user, a change log with `seq` tokens, per-record change
/// tags, "if server record unchanged" saves, zone deletion and re-creation (epochs), the `zone-info` generation marker.
/// Like CloudKit it never merges; the newest save wins. Token = "epoch:seq"; meta (system fields) = "epoch:tag".
final class InMemoryCloud: @unchecked Sendable {
    enum Op: Hashable, Sendable { case accountStatus, ensureZone, claimZoneGeneration, fetchChanges, save, delete, deleteZone }

    struct Stored {
        var envelope: SyncRecord
        var tag: Int
        var seq: Int
        var modifiedAt: Int64
    }

    final class Zone {
        let epoch: Int
        var seq = 0
        var records: [ToriID: Stored] = [:]
        var deletions: [(id: ToriID, seq: Int)] = []
        var generation: (value: String, seq: Int)?
        init(epoch: Int) { self.epoch = epoch }
    }

    private let lock = NSLock()
    private var zones: [String: Zone] = [:]
    /// Users whose zone was deleted in iOS Settings: `userDeletedZone` until the app creates the zone again.
    private var deletedInSettings: Set<String> = []
    private var counter = 0
    private var errors: [Op: [CloudError]] = [:]
    private var outcomes: [ToriID: [SaveOutcome]] = [:]
    private(set) var calls: [(user: String, op: Op)] = []
    private var savedBatchSizes: [Int] = []

    /// Cloud modification dates, Unix ms.
    var now: @Sendable () -> Int64
    /// Max changes (records, deletions, the marker) per fetched page.
    var pageLimit = 400

    init(now: @escaping @Sendable () -> Int64) { self.now = now }

    func link(user: String?) -> CloudLink { CloudLink(self, user: user) }

    // MARK: Scripting

    /// The next `times` calls of `op` (any user) fail with `error`.
    func fail(_ op: Op, with error: CloudError, times: Int = 1) {
        lock.withLock { errors[op, default: []] += Array(repeating: error, count: times) }
    }

    /// The next saves of `id` report these outcomes instead of saving (one per save).
    func script(_ id: ToriID, _ results: SaveOutcome...) {
        lock.withLock { outcomes[id, default: []] += results }
    }

    /// A newer client wrote these records (`upgradeSchema`): stored as-is, newest wins. Creates the zone if absent.
    func inject(user: String, _ records: [SyncRecord]) {
        lock.withLock {
            let zone = zoneCreating(user)
            for r in records { store(zone, r) }
        }
    }

    /// "Delete iCloud data" in iOS Settings (`userDeletedZone`), unlike the app's own `deleteZone` (`zoneNotFound`).
    func deleteZoneInSettings(user: String) {
        lock.withLock {
            zones[user] = nil
            deletedInSettings.insert(user)
        }
    }

    private var interleaved: (@Sendable () async -> Void)?

    /// Runs `body` once, right before the next save (another device writing between this device's pull and push).
    func beforeNextSave(_ body: @escaping @Sendable () async -> Void) { lock.withLock { interleaved = body } }

    /// Every save request's size, including failed ones.
    func noteBatch(_ size: Int) { lock.withLock { savedBatchSizes.append(size) } }

    func takeInterleaved() -> (@Sendable () async -> Void)? {
        lock.withLock {
            defer { interleaved = nil }
            return interleaved
        }
    }

    // MARK: Inspection

    func zone(_ user: String) -> Zone? { lock.withLock { zones[user] } }
    func records(_ user: String) -> [ToriID: SyncRecord] { lock.withLock { zones[user]?.records.mapValues(\.envelope) ?? [:] } }
    func generation(_ user: String) -> String? { lock.withLock { zones[user]?.generation?.value } }
    func count(_ op: Op) -> Int { lock.withLock { calls.filter { $0.op == op }.count } }
    var batchSizes: [Int] { lock.withLock { savedBatchSizes } }

    // MARK: Operations (called through `CloudLink`)

    func perform<T>(_ user: String, _ op: Op, _ body: () throws -> T) throws -> T {
        try lock.withLock {
            calls.append((user, op))
            if var queue = errors[op], !queue.isEmpty {
                let e = queue.removeFirst()
                errors[op] = queue
                throw e
            }
            return try body()
        }
    }

    func ensureZone(_ user: String) {
        _ = zoneCreating(user)
        deletedInSettings.remove(user)
    }

    func claim(_ user: String, _ generation: String) throws -> String {
        let zone = try existing(user)
        if let current = zone.generation { return current.value }
        zone.seq += 1
        zone.generation = (generation, zone.seq)
        return generation
    }

    func fetch(_ user: String, token: Data?) throws -> CloudChanges {
        let zone = try existing(user)
        var since = 0
        if let token {
            let parts = String(decoding: token, as: UTF8.self).split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, parts[0] == zone.epoch else { throw CloudError.changeTokenExpired }
            since = parts[1]
        }
        enum Change { case record(Stored), deletion(ToriID), marker(String) }
        var changes: [(seq: Int, change: Change)] = zone.records.values.filter { $0.seq > since }.map { ($0.seq, .record($0)) }
        changes += zone.deletions.filter { $0.seq > since && zone.records[$0.id] == nil }.map { ($0.seq, .deletion($0.id)) }
        if let g = zone.generation, g.seq > since { changes.append((g.seq, .marker(g.value))) }
        changes.sort { $0.seq < $1.seq }
        let page = changes.prefix(pageLimit)
        var out = CloudChanges(records: [], deletedIDs: [], zoneGeneration: nil, token: Data("\(zone.epoch):\(page.last?.seq ?? since)".utf8),
                               moreComing: changes.count > page.count)
        for (_, change) in page {
            switch change {
            case .record(let s): out.records.append(cloudRecord(zone, s))
            case .deletion(let id): out.deletedIDs.append(id)
            case .marker(let g): out.zoneGeneration = g
            }
        }
        return out
    }

    func save(_ user: String, _ records: [CloudRecord]) throws -> [ToriID: SaveOutcome] {
        let zone = try existing(user)
        var result: [ToriID: SaveOutcome] = [:]
        for r in records {
            let id = r.envelope.id
            if var queue = outcomes[id], !queue.isEmpty {
                result[id] = queue.removeFirst()
                outcomes[id] = queue
                continue
            }
            if let server = zone.records[id] {
                guard r.meta == meta(zone, server.tag) else {
                    result[id] = .conflict(cloudRecord(zone, server))
                    continue
                }
            } else if r.meta != nil {
                result[id] = .unknownItem
                continue
            }
            let s = store(zone, r.envelope)
            result[id] = .saved(meta: meta(zone, s.tag), modifiedAt: s.modifiedAt)
        }
        return result
    }

    func delete(_ user: String, _ ids: [ToriID]) throws {
        let zone = try existing(user)
        for id in ids where zone.records.removeValue(forKey: id) != nil {
            zone.seq += 1
            zone.deletions.append((id, zone.seq))
        }
    }

    func deleteZone(_ user: String) throws {
        guard zones.removeValue(forKey: user) != nil else { throw CloudError.zoneNotFound }
    }

    // MARK: Internals (lock held)

    private func existing(_ user: String) throws -> Zone {
        if let zone = zones[user] { return zone }
        throw deletedInSettings.contains(user) ? CloudError.zoneDeleted : CloudError.zoneNotFound
    }

    private func zoneCreating(_ user: String) -> Zone {
        if let zone = zones[user] { return zone }
        counter += 1
        let zone = Zone(epoch: counter)
        zones[user] = zone
        return zone
    }

    @discardableResult
    private func store(_ zone: Zone, _ envelope: SyncRecord) -> Stored {
        counter += 1
        zone.seq += 1
        let s = Stored(envelope: envelope, tag: counter, seq: zone.seq, modifiedAt: now())
        zone.records[envelope.id] = s
        return s
    }

    private func meta(_ zone: Zone, _ tag: Int) -> Data { Data("\(zone.epoch):\(tag)".utf8) }

    private func cloudRecord(_ zone: Zone, _ s: Stored) -> CloudRecord {
        CloudRecord(envelope: s.envelope, meta: meta(zone, s.tag), modifiedAt: s.modifiedAt)
    }
}

/// One device's view of the cloud: its iCloud user (nil = iCloud off) and network.
final class CloudLink: CloudDatabase, @unchecked Sendable {
    private let lock = NSLock()
    private let cloud: InMemoryCloud
    private var _user: String?
    private var _online = true

    init(_ cloud: InMemoryCloud, user: String?) {
        self.cloud = cloud
        _user = user
    }

    var user: String? {
        get { lock.withLock { _user } }
        set { lock.withLock { _user = newValue } }
    }

    var online: Bool {
        get { lock.withLock { _online } }
        set { lock.withLock { _online = newValue } }
    }

    private func run<T>(_ op: InMemoryCloud.Op, _ body: (String) throws -> T) throws -> T {
        guard let user else { throw CloudError.notAuthenticated }
        guard online else { throw CloudError.network }
        return try cloud.perform(user, op) { try body(user) }
    }

    func accountStatus() async throws -> CloudAccount {
        guard let user else { return .unavailable }
        return try cloud.perform(user, .accountStatus) { .available(userID: user) }
    }

    func ensureZone() async throws { try run(.ensureZone) { cloud.ensureZone($0) } }
    func claimZoneGeneration(_ generation: String) async throws -> String { try run(.claimZoneGeneration) { try cloud.claim($0, generation) } }
    func fetchChanges(token: Data?) async throws -> CloudChanges { try run(.fetchChanges) { try cloud.fetch($0, token: token) } }
    func save(_ records: [CloudRecord]) async throws -> [ToriID: SaveOutcome] {
        if let interleaved = cloud.takeInterleaved() { await interleaved() }
        cloud.noteBatch(records.count)
        return try run(.save) { try cloud.save($0, records) }
    }
    func delete(_ ids: [ToriID]) async throws { try run(.delete) { try cloud.delete($0, ids) } }
    func deleteZone() async throws { try run(.deleteZone) { try cloud.deleteZone($0) } }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64
    init(_ v: Int64) { value = v }
    var ms: Int64 {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// A simulated device: real ToriStore + SyncEngine on a temp database, against `InMemoryCloud`.
final class CloudDevice: @unchecked Sendable {
    let name: String
    let store: ToriStore
    let engine: SyncEngine
    let link: CloudLink
    let offset: TestClock

    init(name: String, cloud: InMemoryCloud, user: String?, clock: TestClock, offsetMs: Int64 = 0,
         sleep: @escaping @Sendable (Int64) async throws -> Void = { _ in throw CancellationError() }) async throws {
        self.name = name
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let offset = TestClock(offsetMs)
        self.offset = offset
        let now: @Sendable () -> Int64 = { clock.ms + offset.ms }
        store = try ToriStore(path: dir.appendingPathComponent("user.sqlite").path, now: now)
        try store.launch(deviceMarker: dir.appendingPathComponent("marker"), displayName: name)
        link = cloud.link(user: user)
        engine = SyncEngine(.init(store: store, cloud: link, appVersion: "1.0.0", now: now, sleep: sleep, jitter: { 0.5 }))
        try await engine.start()
    }
}
