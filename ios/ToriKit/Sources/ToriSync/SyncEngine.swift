import Foundation
import ToriCore
import ToriStore

/// Sync state machine.
public enum SyncState: Equatable, Sendable {
    case localOnly
    case firstSync
    case syncing
    case synced
    case waitingForNetwork
    case unreachable
    case clockSkew
    case updateRequired
    /// Account prompt cancelled or open: "Sync paused: choose what to do with N words".
    case paused(words: Int)
}

/// One-time messages for the UI, shown in order and removed with `dismissNotice()`.
public enum SyncNotice: Equatable, Sendable {
    /// Account prompt "Words from another account".
    case accountPrompt(words: Int)
    /// "No internet connection" / "Connect to the internet to remove these words. Nothing was changed."
    case removeNeedsNetwork
    /// "You were signed out. Sign in again to continue syncing."
    case signedOut
    /// "Your ToriWords account was deleted on another device. Your words stay on this device only."
    case accountDeletedElsewhere
    /// "Vocabulary merged — X words from this device, Y from your account, Z in both."
    case mergeSummary(fromDevice: Int, fromAccount: Int, inBoth: Int)
    /// "Your vocabulary is backed up."
    case backedUp
}

/// The observable value for the Account screen: a plain struct, so an `@Observable` model can mirror it.
public struct SyncStatus: Equatable, Sendable {
    public var state: SyncState
    /// Device-time check: response `Date` more than 1 h off. Shows "Check your device time"; never blocks sync.
    public var clockWarning: Bool
    /// Unix ms.
    public var lastSyncAt: Int64?
    public var notices: [SyncNotice]

    public var syncNowEnabled: Bool {
        switch state {
        case .localOnly, .firstSync, .syncing, .updateRequired, .paused: false
        case .synced, .waitingForNetwork, .unreachable, .clockSkew: true
        }
    }
}

public enum SyncTrigger: Sendable { case foreground, localChange, manual, signIn, backgroundRefresh, networkPath, backoff }

public enum SignInResult: Equatable, Sendable {
    /// Merged silently; the first cycle ran (it may have ended offline).
    case syncing
    /// `pendingAccountChoice` set; the prompt is in `notices`.
    case accountPrompt(words: Int)
    /// N = 0: the silent "Remove" ran, or waits for the network.
    case silentRemove
}

public enum AccountChoice: Sendable { case add, remove }

public enum ChoiceResult: Equatable, Sendable {
    case done
    /// "Remove" offline: refused, nothing changed, prompt stays.
    case needsNetwork
    /// The session was lost during the pre-resolution check; nothing changed locally.
    case sessionLost
    case noPendingChoice
}

/// Network backoff: 5 s, 10 s, 20 s … 15 min, ±20 % jitter.
public enum Backoff {
    public static func delayMs(attempt: Int, jitter: Double) -> Int64 {
        let base = min(5_000 * pow(2, Double(min(attempt, 20))), 900_000)
        return Int64(base * (0.8 + 0.4 * min(max(jitter, 0), 1)))
    }
}

/// `pendingAccountChoice` value.
struct PendingChoice: Codable, Equatable {
    var newAccountId: String
    var previousAccountId: String
    var setAt: Int64
}

struct Excluded: Codable {
    var appVersion: String
    var ids: Set<ToriID>
}

/// One sync at a time (push, then paged pull), the account flows that gate it, and the status.
public actor SyncEngine {
    public struct Dependencies: Sendable {
        public var store: ToriStore
        public var transport: any HTTPTransport
        public var sessionStore: any SessionStore
        public var appVersion: String
        public var deviceID: ToriID
        /// Unix ms.
        public var now: @Sendable () -> Int64
        /// Suspends for the given ms (backoff, debounce, Retry-After). Throwing cancels the scheduled work.
        public var sleep: @Sendable (Int64) async throws -> Void
        public var jitter: @Sendable () -> Double
        /// After each cycle: vocab index, widget snapshot and reload, reminders.
        public var afterCycle: @Sendable () async -> Void
        public var pageLimit: Int

        public init(store: ToriStore, transport: any HTTPTransport, sessionStore: any SessionStore, appVersion: String,
                    deviceID: ToriID, now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
                    sleep: @escaping @Sendable (Int64) async throws -> Void = { try await Task.sleep(for: .milliseconds($0)) },
                    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
                    afterCycle: @escaping @Sendable () async -> Void = {}, pageLimit: Int = 1000) {
            self.store = store
            self.transport = transport
            self.sessionStore = sessionStore
            self.appVersion = appVersion
            self.deviceID = deviceID
            self.now = now
            self.sleep = sleep
            self.jitter = jitter
            self.afterCycle = afterCycle
            self.pageLimit = pageLimit
        }
    }

    public static let maxBatchRecords = 500
    public static let maxBatchBytes = 2_000_000
    public static let maxRecordBytes = 64 * 1024

    let deps: Dependencies
    let store: ToriStore
    let api: APIClient
    public let sessions: SessionManager
    private let timeCheck: DeviceTimeCheck

    public private(set) var status: SyncStatus
    private var continuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private var running = false
    private var rerun = false
    private var updateRequired = false
    private var backoffAttempt = 0
    private var retryTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    /// The page limit for the next pulls (tests page small).
    public var pageLimit: Int

    public init(_ deps: Dependencies) {
        self.deps = deps
        store = deps.store
        let check = DeviceTimeCheck(store: deps.store, now: deps.now)
        timeCheck = check
        api = APIClient(transport: deps.transport, appVersion: deps.appVersion, deviceID: deps.deviceID,
                        onServerTime: { check.observe($0) })
        sessions = SessionManager(api: api, store: deps.sessionStore, now: deps.now)
        pageLimit = deps.pageLimit
        status = SyncStatus(state: .localOnly, clockWarning: false, lastSyncAt: nil, notices: [])
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

    public func dismissNotice() {
        guard !status.notices.isEmpty else { return }
        status.notices.removeFirst()
        publish()
    }

    private func set(_ state: SyncState) {
        status.state = state
        publish()
    }

    private func notify(_ n: SyncNotice) {
        status.notices.append(n)
        publish()
    }

    private func publish() {
        status.clockWarning = timeCheck.warning
        status.lastSyncAt = (try? store.syncState(.lastSyncAt)).flatMap { $0.flatMap { Int64($0) } }
        for c in continuations.values { c.yield(status) }
    }

    // MARK: Launch and triggers

    /// Launch reconciliation of the account keys and the initial state. Call once after `ToriStore.launch`.
    public func start() async throws {
        await sessions.setLossHandler { [weak self] loss in await self?.sessionLost(loss) }
        let session = await sessions.current
        if let pending = try pendingChoice(), session?.accountId != pending.newAccountId {
            try store.setSyncState([.pendingAccountChoice: nil])
        }
        if let adopted = try store.syncState(.adoptedAccountId), session?.accountId != adopted {
            try store.setSyncState([.adoptedAccountId: nil])
        }
        let account = try store.syncState(.accountId)
        if session == nil, account != nil { try store.enterLocalOnly() }
        if let session, account != session.accountId {
            // Sign-in interrupted before the account was stored: nothing was synced, start over.
            await sessions.discard()
            if account != nil { try store.enterLocalOnly() }
        }
        try refreshState()
    }

    /// App foreground: session check (also while paused), then a cycle.
    public func foreground() async {
        await sessions.foregroundCheck()
        await sync(.foreground)
    }

    public func background() async { await sessions.foregroundEnded() }

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
        guard satisfied, status.state == .waitingForNetwork || status.state == .unreachable else { return }
        retryTask?.cancel()
        await sync(.networkPath)
    }

    /// Runs one cycle, or coalesces into the running one. No-op while signed out, paused or update-required.
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

    /// `push: false` / `pull: false` only for tests (`pullOnly`, `pushOnly` fixture ops).
    func cycle(push doPush: Bool = true, pull doPull: Bool = true) async {
        guard !updateRequired, await sessions.current != nil, (try? store.syncState(.accountId)) ?? nil != nil else { return }
        do {
            if try pendingChoice() != nil {
                if try store.liveEntryCount() == 0 { _ = await removeLocalData(silent: true) }
                return
            }
            if try await guardFires() { return }
            set(try store.syncState(.cursor) == nil ? .firstSync : .syncing)
            if let last = try store.syncState(.lastServerTime).flatMap({ Int64($0) }) {
                try store.recoverClockAhead(lastServerTime: last)
            }
            if doPush { try await push() }
            if doPull { try await pull() }
            backoffAttempt = 0
            set(.synced)
            if doPush && doPull { try showMergeSummaryIfPending() }
            await deps.afterCycle()
        } catch let e as APIError {
            handle(e)
        } catch is ClockSkewPersists {
            set(.clockSkew)
        } catch {
            set(.unreachable)
            scheduleRetry()
        }
    }

    struct ClockSkewPersists: Error {}

    private func handle(_ e: APIError) {
        switch e {
        case .offline:
            set(.waitingForNetwork)
            scheduleRetry()
        case .rateLimited(let seconds):
            set(.synced)
            scheduleRetry(afterMs: Int64(seconds) * 1000)
        case .upgradeRequired:
            updateRequired = true
            set(.updateRequired)
        case .sessionRevoked, .accountDeleted:
            break  // `sessionLost` already moved to local-only
        default:
            set(.unreachable)
            scheduleRetry()
        }
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

    /// After any successful push or pull.
    private func markSynced() throws {
        guard let account = try store.syncState(.accountId) else { return }
        try store.setSyncState([.lastSyncedAccountId: account, .adoptedAccountId: nil, .lastSyncAt: String(deps.now())])
    }

    private func push() async throws {
        var excluded = try excludedRecords()
        var maxRecords = Self.maxBatchRecords
        var skewRetried = false
        var lastRows: [OutboxRow]?
        while true {
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
            // A server that acks nothing must not spin the loop.
            guard batch.rows != lastRows else { return }
            lastRows = batch.rows
            do {
                let records = batch.records
                let acked = try await sessions.authorized { [api] token in try await api.push(records, accessToken: token).value }
                try store.acknowledge(batch.rows, acked: acked)
                try markSynced()
            } catch let APIError.invalidRecord(ids) {
                excluded.formUnion(ids)
                try saveExcluded(excluded)
            } catch let APIError.tooLarge(ids) where !ids.isEmpty {
                excluded.formUnion(ids)
                try saveExcluded(excluded)
            } catch APIError.tooLarge {
                guard maxRecords > 1 else { throw APIError.tooLarge(recordIDs: []) }
                maxRecords /= 2
            } catch let APIError.clockSkew(serverTime, _) {
                try store.setSyncState([.lastServerTime: String(serverTime)])
                guard !skewRetried else { throw ClockSkewPersists() }
                skewRetried = true
                try store.recoverClockAhead(lastServerTime: serverTime)
                lastRows = nil
            }
        }
    }

    /// Records within 64 KB, then as many as fit in 2 MB (encoded JSON).
    static func fit(_ records: [SyncRecord]) -> (fitting: [SyncRecord], oversized: [ToriID]) {
        var total = 0, fitting: [SyncRecord] = [], oversized: [ToriID] = []
        for r in records {
            let size = (try? APIClient.encoder.encode(r).count) ?? 0
            if size > maxRecordBytes { oversized.append(r.id); continue }
            guard total + size <= maxBatchBytes else { break }
            total += size
            fitting.append(r)
        }
        return (fitting, oversized)
    }

    private func pull() async throws {
        var cursor = try store.syncState(.cursor) ?? "0"
        let limit = pageLimit
        while true {
            let since = cursor
            let page = try await sessions.authorized { [api] token in
                try await api.pull(since: since, limit: limit, accessToken: token).value
            }
            try store.applyPulledPage(page.records, cursor: page.cursor)
            try markSynced()
            cursor = page.cursor
            if !page.hasMore { return }
        }
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

    // MARK: Sign-in

    public func signIn(_ credential: SignInCredential) async throws -> SignInResult {
        let response = try await sessions.signIn(credential)
        let session = Session(response)
        let newAccount = response.accountId
        let previous = try store.syncState(.lastSyncedAccountId)
        try store.setSyncState([.lastProvider: response.provider])
        if let previous, previous != newAccount, try store.hasUserRecordsBeyondDefaults() {
            let choice = PendingChoice(newAccountId: newAccount, previousAccountId: previous, setAt: deps.now())
            try store.setSyncState([.pendingAccountChoice: try Self.json(choice), .accountId: newAccount])
            try await sessions.persist(session)
            return try await promptOrSilentRemove()
        }
        try await sessions.persist(session)
        if previous == nil {
            let baseline = try store.liveEntryGroups().keys.map(\.description).sorted()
            try store.setSyncState([.signInBaseline: try Self.json(baseline)])
        }
        try store.beginSyncing(account: newAccount, adopted: false)
        await sync(.signIn)
        return .syncing
    }

    private func promptOrSilentRemove() async throws -> SignInResult {
        let n = try store.liveEntryCount()
        if n > 0 {
            set(.paused(words: n))
            notify(.accountPrompt(words: n))
            return .accountPrompt(words: n)
        }
        _ = await removeLocalData(silent: true)
        return .silentRemove
    }

    /// Pre-sync guard (foreign-account data on the device); true when it set the choice instead of syncing.
    private func guardFires() async throws -> Bool {
        guard let account = try store.syncState(.accountId), let last = try store.syncState(.lastSyncedAccountId),
              last != account, try store.hasUserRecordsBeyondDefaults(),
              try store.syncState(.adoptedAccountId) != account else { return false }
        let choice = PendingChoice(newAccountId: account, previousAccountId: last, setAt: deps.now())
        try store.setSyncState([.pendingAccountChoice: try Self.json(choice)])
        _ = try await promptOrSilentRemove()
        return true
    }

    /// "Add these N words to this account" / "Remove all N words from this device". Cancel needs no call.
    public func resolveAccountChoice(_ choice: AccountChoice) async -> ChoiceResult {
        guard (try? pendingChoice()) ?? nil != nil else { return .noPendingChoice }
        switch choice {
        case .remove:
            return await removeLocalData(silent: false)
        case .add:
            do {
                try await sessions.validate()
            } catch APIError.offline, APIError.unreachable {
                // "Add" proceeds offline.
            } catch {
                return .sessionLost
            }
            guard let account = await sessions.current?.accountId else { return .sessionLost }
            do { try store.beginSyncing(account: account, adopted: true) } catch { return .noPendingChoice }
            await sync(.manual)
            return .done
        }
    }

    private func removeLocalData(silent: Bool) async -> ChoiceResult {
        do {
            try await sessions.validate()
        } catch APIError.offline, APIError.unreachable {
            if silent { set(.waitingForNetwork) } else { notify(.removeNeedsNetwork) }
            return .needsNetwork
        } catch {
            return .sessionLost
        }
        do { try store.removeAllUserRecords() } catch { return .noPendingChoice }
        if !running {
            await sync(.manual)
        } else {
            rerun = true
        }
        return .done
    }

    // MARK: Merge summary

    private func showMergeSummaryIfPending() throws {
        guard let text = try store.syncState(.signInBaseline) else { return }
        let baseline = Set((try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? [])
        try store.setSyncState([.signInBaseline: nil])
        var device = 0, account = 0, both = 0
        for members in try store.liveEntryGroups().values {
            let local = members.contains { baseline.contains($0.description) }
            let remote = members.contains { !baseline.contains($0.description) }
            switch (local, remote) {
            case (true, true): both += 1
            case (true, false): device += 1
            case (false, true): account += 1
            case (false, false): break
            }
        }
        if device + both > 0, account + both > 0 {
            notify(.mergeSummary(fromDevice: device, fromAccount: account, inBoth: both))
        } else if device > 0 {
            notify(.backedUp)
        }
    }

    // MARK: Sign-out, deletion, loss

    /// Local-first: logout is best effort; tokens, cursor, choice keys and outbox go; data and `lastSyncedAccountId` stay.
    public func signOut() async throws {
        if let token = await sessions.current?.accessToken { try? await api.logout(accessToken: token) }
        await sessions.discard()
        retryTask?.cancel()
        try store.enterLocalOnly()
        try refreshState()
    }

    /// `DELETE /account` (needs network; throws `APIError`), then local-only, wiping local data if asked.
    public func deleteAccount(removeLocalData: Bool) async throws {
        try await sessions.authorized { [api] token in try await api.deleteAccount(accessToken: token) }
        await sessions.discard()
        retryTask?.cancel()
        if removeLocalData {
            try store.removeAllDataFromDevice(signOut: {})
        } else {
            try store.enterLocalOnly()
        }
        try refreshState()
    }

    private func sessionLost(_ loss: SessionLoss) {
        retryTask?.cancel()
        try? store.enterLocalOnly()
        status.state = .localOnly
        notify(loss == .accountDeleted ? .accountDeletedElsewhere : .signedOut)
    }

    // MARK: Helpers

    private func pendingChoice() throws -> PendingChoice? {
        try store.syncState(.pendingAccountChoice).flatMap { try? JSONDecoder().decode(PendingChoice.self, from: Data($0.utf8)) }
    }

    /// State from storage alone (launch, sign-out).
    private func refreshState() throws {
        if try store.syncState(.accountId) == nil {
            set(.localOnly)
        } else if try pendingChoice() != nil {
            let n = try store.liveEntryCount()
            set(n > 0 ? .paused(words: n) : .waitingForNetwork)
        } else {
            set(try store.syncState(.lastSyncAt) == nil ? .firstSync : .synced)
        }
    }

    static func json(_ v: some Encodable) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return String(decoding: try e.encode(v), as: UTF8.self)
    }
}

/// Device-time check from response `Date` headers; also stores `lastServerTime`.
final class DeviceTimeCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var _warning = false
    let store: ToriStore
    let now: @Sendable () -> Int64

    init(store: ToriStore, now: @escaping @Sendable () -> Int64) {
        self.store = store
        self.now = now
    }

    var warning: Bool { lock.withLock { _warning } }

    func observe(_ serverTime: Int64) {
        let off = abs(now() - serverTime) > HLCState.hourMs
        lock.withLock { _warning = off }
        try? store.setSyncState([.lastServerTime: String(serverTime)])
    }
}
