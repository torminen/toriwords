import Foundation
import ToriCore
import ToriStore

/// Sync state machine.
public enum SyncState: Equatable, Sendable {
    /// Never synced on this install yet.
    case idle
    case syncing
    /// Unix ms of the last completed cycle.
    case synced(at: Int64)
    case waitingForNetwork
    /// "iCloud is off: words stay on this device". The outbox keeps queueing.
    case iCloudOff
    /// "iCloud storage is full"; retried on the next trigger.
    case quotaFull
    /// "iCloud data was deleted": no sync until "Back up this device again".
    case cloudDeleted
}

/// The observable value for the iCloud sync screen.
public struct SyncStatus: Equatable, Sendable {
    public var state: SyncState
    /// Device time more than 1 h off the cloud's modification date of a record just saved. Never blocks sync.
    public var clockWarning: Bool

    public var syncNowEnabled: Bool {
        switch state {
        case .syncing, .iCloudOff, .cloudDeleted: false
        case .idle, .synced, .waitingForNetwork, .quotaFull: true
        }
    }
}

public enum SyncTrigger: Sendable { case foreground, localChange, manual, backgroundRefresh, networkPath, backoff }

/// Network backoff: 5 s, 10 s, 20 s … 15 min, ±20 % jitter.
public enum Backoff {
    public static func delayMs(attempt: Int, jitter: Double) -> Int64 {
        let base = min(5_000 * pow(2, Double(min(attempt, 20))), 900_000)
        return Int64(base * (0.8 + 0.4 * min(max(jitter, 0), 1)))
    }
}

struct Excluded: Codable {
    var appVersion: String
    var ids: Set<ToriID>
}

/// One sync at a time against the iCloud private database: account check, zone, pull, push, cloud purge.
/// The cloud never merges; this client merges every record (HLC per field) and stores the merged envelope back.
public actor SyncEngine {
    public struct Dependencies: Sendable {
        public var store: ToriStore
        public var cloud: any CloudDatabase
        public var appVersion: String
        /// Unix ms.
        public var now: @Sendable () -> Int64
        /// Suspends for the given ms (backoff, debounce, retry-after). Throwing cancels the scheduled work.
        public var sleep: @Sendable (Int64) async throws -> Void
        public var jitter: @Sendable () -> Double
        /// A new `zone-info` generation.
        public var newGeneration: @Sendable () -> String
        /// After each cycle: vocab index, widget snapshot and reload, reminders.
        public var afterCycle: @Sendable () async -> Void

        public init(store: ToriStore, cloud: any CloudDatabase, appVersion: String,
                    now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
                    sleep: @escaping @Sendable (Int64) async throws -> Void = { try await Task.sleep(for: .milliseconds($0)) },
                    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
                    newGeneration: @escaping @Sendable () -> String = { UUID().uuidString },
                    afterCycle: @escaping @Sendable () async -> Void = {}) {
            self.store = store
            self.cloud = cloud
            self.appVersion = appVersion
            self.now = now
            self.sleep = sleep
            self.jitter = jitter
            self.newGeneration = newGeneration
            self.afterCycle = afterCycle
        }
    }

    public static let maxBatchRecords = 300
    public static let maxBatchBytes = 2_000_000
    public static let maxRecordBytes = 64 * 1024
    /// Push rounds in a row that saved nothing (conflicts, retries) before the cycle gives up until the next trigger.
    static let maxStalledRounds = 3

    let deps: Dependencies
    let store: ToriStore
    let cloud: any CloudDatabase

    public private(set) var status = SyncStatus(state: .idle, clockWarning: false)
    private var continuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private var running = false
    private var rerun = false
    /// Bumped by store resets (Remove all data, Delete iCloud data, Back up again). A cycle started under an older
    /// epoch stops at its next await instead of writing a stale change token, meta or status.
    private var epoch = 0
    private var backoffAttempt = 0
    private var retryTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    public init(_ deps: Dependencies) {
        self.deps = deps
        store = deps.store
        cloud = deps.cloud
    }

    // MARK: Status

    /// Current status first, then every change.
    public func statusUpdates() -> AsyncStream<SyncStatus> {
        let (stream, continuation) = AsyncStream<SyncStatus>.makeStream()
        let id = UUID()
        continuations[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in Task { await self?.removeContinuation(id) } }
        return stream
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }

    private func set(_ state: SyncState) {
        status.state = state
        publish()
    }

    private func publish() {
        for c in continuations.values { c.yield(status) }
    }

    // MARK: Launch and triggers

    /// The state from storage alone. Call once after `ToriStore.launch`.
    public func start() throws {
        if try store.syncState(.cloudDeleted) != nil {
            set(.cloudDeleted)
        } else if let at = try store.syncState(.lastSyncAt).flatMap({ Int64($0) }) {
            set(.synced(at: at))
        } else {
            set(.idle)
        }
    }

    public func foreground() async { await sync(.foreground) }

    /// Leaving the foreground: pending local edits go out now instead of after the debounce.
    public func background() async {
        guard debounceTask != nil else { return }
        debounceTask?.cancel()
        debounceTask = nil
        await sync(.localChange)
    }

    /// ~5 s after the last local change.
    public func localChange() {
        debounceTask?.cancel()
        debounceTask = Task { [deps] in
            guard (try? await deps.sleep(5_000)) != nil else { return }
            await self.sync(.localChange)
        }
    }

    /// `NWPathMonitor`: a satisfied path after a network failure re-runs sync at once.
    public func networkPathChanged(satisfied: Bool) async {
        guard satisfied, status.state == .waitingForNetwork else { return }
        retryTask?.cancel()
        await sync(.networkPath)
    }

    /// Runs one cycle, or coalesces into the running one.
    public func sync(_ trigger: SyncTrigger = .manual) async {
        if running {
            rerun = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            rerun = false
            await cycle()
        } while rerun
    }

    // MARK: Cycle

    /// The zone was replaced by another device's "Back up this device again" (a new `zone-info` generation).
    struct ZoneReplaced: Error {}

    /// The cycle was superseded by a store reset while it was suspended.
    struct Superseded: Error {}

    /// Called after every `await` in a cycle, before it writes anything.
    private func check(_ started: Int) throws {
        if started != epoch { throw Superseded() }
    }

    func cycle() async {
        let started = epoch
        do {
            let account = try await cloud.accountStatus()
            try check(started)
            guard case .available(let user) = account else { return set(.iCloudOff) }
            // First availability or an iCloud account switch: the local data merges silently into this account.
            if try store.syncState(.cloudUser) != user { try store.activateCloud(user: user) }
            guard try store.syncState(.cloudDeleted) == nil else { return set(.cloudDeleted) }
            set(.syncing)
            if let last = try store.syncState(.lastServerTime).flatMap({ Int64($0) }) {
                try store.recoverClockAhead(lastServerTime: last)
            }
            try await prepareZone(started)
            try await pull(started)
            try await push(started)
            try await deleteQueued(started)
            try check(started)
            backoffAttempt = 0
            let at = deps.now()
            try store.setSyncState([.lastSyncAt: String(at)])
            set(.synced(at: at))
            await deps.afterCycle()
        } catch is Superseded {
            return
        } catch where started != epoch {
            return  // a reset happened while this cycle was suspended; its error is stale
        } catch CloudError.zoneNotFound, CloudError.zoneDeleted {
            zoneGone()
        } catch is ZoneReplaced {
            zoneGone()
        } catch let e as CloudError {
            handle(e)
        } catch {
            set(.waitingForNetwork)
            scheduleRetry()
        }
    }

    private func handle(_ e: CloudError) {
        switch e {
        case .rateLimited(let seconds):
            restingState()
            scheduleRetry(afterMs: Int64(seconds) * 1000)
        case .quotaExceeded:
            set(.quotaFull)
        case .notAuthenticated:
            set(.iCloudOff)
        case .zoneDeleted, .zoneNotFound:
            zoneGone()
        case .network, .changeTokenExpired, .limitExceeded, .unknownItem, .other:
            set(.waitingForNetwork)
            scheduleRetry()
        }
    }

    /// Deleted here, in iOS Settings, or on another device: keep the words, stop syncing.
    private func zoneGone() {
        retryTask?.cancel()
        try? store.markCloudDeleted()
        set(.cloudDeleted)
    }

    private func restingState() {
        let at = (try? store.syncState(.lastSyncAt)).flatMap { $0.flatMap { Int64($0) } }
        set(at.map { .synced(at: $0) } ?? .idle)
    }

    private func scheduleRetry(afterMs: Int64? = nil) {
        let delay = afterMs ?? Backoff.delayMs(attempt: backoffAttempt, jitter: deps.jitter())
        if afterMs == nil { backoffAttempt += 1 }
        retryTask?.cancel()
        retryTask = Task { [deps] in
            guard (try? await deps.sleep(delay)) != nil else { return }
            await self.sync(.backoff)
        }
    }

    /// Zone created once per `cloudUser`; the first writer's `zone-info` generation is adopted by every device.
    private func prepareZone(_ started: Int) async throws {
        if try store.syncState(.zoneCreated) == nil {
            try await cloud.ensureZone()
            try check(started)
            try store.setSyncState([.zoneCreated: "1"])
        }
        if try store.syncState(.zoneGeneration) == nil {
            let generation = try await cloud.claimZoneGeneration(deps.newGeneration())
            try check(started)
            try store.setSyncState([.zoneGeneration: generation])
        }
    }

    private func pull(_ started: Int) async throws {
        var token = try store.syncState(.changeToken).flatMap { Data(base64Encoded: $0) }
        var refetched = false
        while true {
            let changes: CloudChanges
            do {
                changes = try await cloud.fetchChanges(token: token)
                try check(started)
            } catch CloudError.changeTokenExpired where !refetched && started == epoch {
                refetched = true
                token = nil
                try store.setSyncState([.changeToken: nil])
                continue
            }
            if let generation = changes.zoneGeneration, try generation != store.syncState(.zoneGeneration) { throw ZoneReplaced() }
            try store.applyCloudChanges(changes.records.map(\.envelope), meta: Self.meta(changes.records),
                                        deletedIDs: changes.deletedIDs, token: changes.token.base64EncodedString())
            try observeCloudTime(changes.records.map(\.modifiedAt), fresh: false)
            token = changes.token
            if !changes.moreComing { return }
        }
    }

    private func push(_ started: Int) async throws {
        var excluded = try excludedRecords()
        var maxRecords = Self.maxBatchRecords
        var stalled = 0
        while stalled < Self.maxStalledRounds {
            var batch = try store.pendingPush(maxRecords: maxRecords, excluding: excluded)
            guard !batch.records.isEmpty else { return }
            let (fitting, oversized) = Self.fit(batch.records)
            if !oversized.isEmpty {
                excluded.formUnion(oversized)
                try saveExcluded(excluded)
                continue
            }
            if fitting.count < batch.records.count {
                let keep = Set(fitting.map(\.id))
                batch = PushBatch(records: fitting, rows: batch.rows.filter { keep.contains($0.recordID) })
            }
            let meta = try store.cloudMeta(batch.records.map(\.id))
            let outcomes: [ToriID: SaveOutcome]
            do {
                outcomes = try await cloud.save(batch.records.map { CloudRecord(envelope: $0, meta: meta[$0.id], modifiedAt: 0) })
                try check(started)
            } catch CloudError.limitExceeded where maxRecords > 1 && started == epoch {
                maxRecords = max(1, batch.records.count / 2)
                continue
            }
            var saved: [ToriID: Data] = [:], conflicts: [CloudRecord] = [], unknown: [ToriID] = [], modified: [Int64] = []
            for (id, outcome) in outcomes {
                switch outcome {
                case .saved(let m, let at):
                    saved[id] = m
                    modified.append(at)
                case .conflict(let server): conflicts.append(server)
                case .unknownItem: unknown.append(id)
                case .retry: break
                case .failed(.limitExceeded), .failed(.unknownItem), .failed(.other), .failed(.changeTokenExpired):
                    excluded.insert(id)
                case .failed(let e): throw e
                }
            }
            if !saved.isEmpty { try store.recordSaved(batch.rows, meta: saved) }
            // Merge the server copy (also its system fields), then the next round re-sends the merged record.
            if !conflicts.isEmpty { try store.applyCloudChanges(conflicts.map(\.envelope), meta: Self.meta(conflicts), token: nil) }
            if !unknown.isEmpty { try store.dropCloudMeta(unknown) }
            if excluded != (try excludedRecords()) { try saveExcluded(excluded) }
            try observeCloudTime(modified, fresh: true)
            stalled = saved.isEmpty ? stalled + 1 : 0
        }
    }

    /// Children of deleted Entry groups, removed from the cloud (tombstones stay).
    private func deleteQueued(_ started: Int) async throws {
        while true {
            let ids = try store.pendingCloudDeletes(limit: Self.maxBatchRecords)
            guard !ids.isEmpty else { return }
            try await cloud.delete(ids)
            try check(started)
            try store.cloudDeletesDone(ids)
        }
    }

    /// `lastServerTime` = the newest cloud modification date seen; `fresh` dates (records just saved) drive the
    /// device-time check.
    private func observeCloudTime(_ dates: [Int64], fresh: Bool) throws {
        guard let latest = dates.max(), latest > 0 else { return }
        if latest > (try store.syncState(.lastServerTime).flatMap { Int64($0) } ?? 0) {
            try store.setSyncState([.lastServerTime: String(latest)])
        }
        if fresh {
            status.clockWarning = abs(deps.now() - latest) > HLCState.hourMs
            publish()
        }
    }

    static func meta(_ records: [CloudRecord]) -> [ToriID: Data] {
        Dictionary(records.compactMap { r in r.meta.map { (r.envelope.id, $0) } }, uniquingKeysWith: { _, b in b })
    }

    /// Records within 64 KB, then as many as fit in 2 MB (encoded JSON).
    static func fit(_ records: [SyncRecord]) -> (fitting: [SyncRecord], oversized: [ToriID]) {
        let encoder = JSONEncoder()
        var total = 0, fitting: [SyncRecord] = [], oversized: [ToriID] = []
        for r in records {
            let size = (try? encoder.encode(r).count) ?? 0
            if size > maxRecordBytes { oversized.append(r.id); continue }
            guard total + size <= maxBatchBytes else { break }
            total += size
            fitting.append(r)
        }
        return (fitting, oversized)
    }

    private func excludedRecords() throws -> Set<ToriID> {
        guard let text = try store.syncState(.excludedRecords),
              let value = try? JSONDecoder().decode(Excluded.self, from: Data(text.utf8)),
              value.appVersion == deps.appVersion else { return [] }
        return value.ids
    }

    private func saveExcluded(_ ids: Set<ToriID>) throws {
        let data = try JSONEncoder().encode(Excluded(appVersion: deps.appVersion, ids: ids))
        try store.setSyncState([.excludedRecords: String(decoding: data, as: UTF8.self)])
    }

    // MARK: Delete iCloud data / Back up again

    /// Settings → iCloud sync → "Delete iCloud data…": deletes the zone (needs the network; throws `CloudError`).
    /// This device keeps its words and stops syncing; other devices stop when they next see the zone gone.
    public func deleteCloudData() async throws {
        epoch += 1  // a suspended cycle must not mark records saved or show "Synced" afterwards
        retryTask?.cancel()
        do { try await cloud.deleteZone() } catch CloudError.zoneNotFound {}
        epoch += 1  // also a cycle that started while the zone was being deleted
        retryTask?.cancel()
        try store.markCloudDeleted()
        set(.cloudDeleted)
    }

    /// Settings → Data → "Remove all data from this device": the store reset (records, outbox, change token, cloud
    /// meta) with any suspended cycle superseded, so the next cycle downloads everything again.
    public func removeAllDataFromDevice() throws {
        epoch += 1
        retryTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        try store.removeAllDataFromDevice()
        try store.setSyncState([.lastSyncAt: nil])  // nothing on the device is synced any more
        status.clockWarning = false
        set(.idle)
    }

    /// "Back up this device again": a new zone generation (or the one another device already re-created), every record
    /// pending, then a cycle.
    public func backUpAgain() async throws {
        epoch += 1
        try store.backUpAgain()
        await sync(.manual)
    }
}
