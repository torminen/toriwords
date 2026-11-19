import Foundation
import Testing
import ToriCore
@testable import ToriStore
@testable import ToriSync

/// 2025-11-10 12:00 UTC.
let t0: Int64 = 1_762_776_000_000

/// Captures the sleeps the engine schedules; never sleeps.
final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []
    func record(_ ms: Int64) { lock.withLock { values.append(ms) } }
    var all: [Int64] { lock.withLock { values } }
}

/// One cloud, devices on the same iCloud user by default.
struct Rig {
    let clock = TestClock(t0)
    let cloud: InMemoryCloud
    let sleeps = SleepLog()

    init() {
        let clock = clock
        cloud = InMemoryCloud { clock.ms }
    }

    func device(_ name: String = "A", user: String? = "alice", offsetMs: Int64 = 0) async throws -> CloudDevice {
        try await CloudDevice(name: name, cloud: cloud, user: user, clock: clock, offsetMs: offsetMs, sleep: { [sleeps] in
            sleeps.record($0)
            throw CancellationError()
        })
    }
}

extension CloudDevice {
    @discardableResult
    func capture(_ term: String, translation: String? = nil) throws -> ToriID {
        let senses = translation.map { [NewSense(translation: $0, source: .wiktionary, dictVersion: "2026.11.1")] } ?? []
        return try store.capture(CaptureInput(term: term, capturedAt: t0, senses: senses, sentence: nil, source: nil, tags: []))
    }

    func sync() async { await engine.sync() }
    var state: SyncState { get async { await engine.status.state } }

    func entry(_ id: ToriID) throws -> SyncRecord? { try store.db.read { try RecordIO.load($0, .entry, id) } }
    func note(_ id: ToriID) throws -> String? {
        guard case .string(let s)? = try entry(id)?.fields["note"]?.value else { return nil }
        return s
    }
    func count(_ table: String) throws -> Int { try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 } }
}

func isSynced(_ s: SyncState) -> Bool { if case .synced = s { true } else { false } }

// MARK: Backoff

@Test func backoffDoublesFromFiveSecondsToFifteenMinutes() {
    #expect((0..<10).map { Backoff.delayMs(attempt: $0, jitter: 0.5) }
            == [5_000, 10_000, 20_000, 40_000, 80_000, 160_000, 320_000, 640_000, 900_000, 900_000])
    #expect(Backoff.delayMs(attempt: 0, jitter: 0) == 4_000)
    #expect(Backoff.delayMs(attempt: 0, jitter: 1) == 6_000)
    #expect(Backoff.delayMs(attempt: 99, jitter: 1) == 1_080_000)
}

// MARK: Zone and generation

@Test func firstSyncUploadsAndSecondDeviceAdoptsTheGeneration() async throws {
    let rig = Rig()
    let a = try await rig.device("A")
    let run = try a.capture("run")
    #expect(await a.state == .idle)
    await a.sync()
    #expect(isSynced(await a.state))
    let generation = try #require(rig.cloud.generation("alice"))
    #expect(try a.store.syncState(.zoneGeneration) == generation)
    #expect(rig.cloud.records("alice")[run] != nil)
    #expect(try a.store.pendingRecordCount() == 0)

    let b = try await rig.device("B")
    await b.sync()
    #expect(isSynced(await b.state))
    #expect(try b.store.syncState(.zoneGeneration) == generation)
    #expect(try b.entry(run) != nil)
    await a.sync()
    #expect(isSynced(await a.state))
    #expect(rig.cloud.generation("alice") == generation)
}

@Test func concurrentFirstSyncsShareOneGeneration() async throws {
    let rig = Rig()
    let a = try await rig.device("A"), b = try await rig.device("B")
    let run = try a.capture("run"), walk = try b.capture("walk")
    async let x: Void = a.sync()
    async let y: Void = b.sync()
    _ = await (x, y)
    await a.sync()
    await b.sync()
    let (sa, sb) = (await a.state, await b.state)
    #expect(isSynced(sa) && isSynced(sb))
    #expect(try a.store.syncState(.zoneGeneration) == b.store.syncState(.zoneGeneration))
    #expect(try a.entry(walk) != nil && b.entry(run) != nil)
}

@Test func zoneDeletedInSettingsStopsSyncAndKeepsWords() async throws {
    let rig = Rig()
    let a = try await rig.device()
    try a.capture("run")
    await a.sync()
    rig.cloud.deleteZoneInSettings(user: "alice")
    await a.sync()
    #expect(await a.state == .cloudDeleted)
    #expect(try a.store.liveEntryCount() == 1)
    try a.capture("walk")
    #expect(try a.store.pendingRecordCount() == 0, "no outbox while cloud data is deleted")
    let fetches = rig.cloud.count(.fetchChanges)
    await a.sync()
    #expect(rig.cloud.count(.fetchChanges) == fetches)
    #expect(await a.state == .cloudDeleted)
}

@Test func deleteCloudDataStopsTheOtherDeviceAndBackUpAgainRecreatesTheZone() async throws {
    let rig = Rig()
    let a = try await rig.device("A"), b = try await rig.device("B")
    let run = try a.capture("run")
    await a.sync()
    await b.sync()
    let old = try #require(rig.cloud.generation("alice"))

    try await a.engine.deleteCloudData()
    #expect(await a.state == .cloudDeleted)
    #expect(rig.cloud.zone("alice") == nil)
    await b.sync()
    #expect(await b.state == .cloudDeleted)
    #expect(try b.entry(run) != nil)

    try await a.engine.backUpAgain()
    #expect(isSynced(await a.state))
    let new = try #require(rig.cloud.generation("alice"))
    #expect(new != old && rig.cloud.records("alice")[run] != nil)
    await b.sync()
    #expect(await b.state == .cloudDeleted, "B stays stopped until its own Back up again")
}

@Test func zoneRecreatedByAnotherDeviceMeansCloudDeleted() async throws {
    let rig = Rig()
    let a = try await rig.device("A"), b = try await rig.device("B")
    try a.capture("run")
    await a.sync()
    await b.sync()
    // A deletes and re-creates the zone before B notices the deletion.
    try await a.engine.deleteCloudData()
    try await a.engine.backUpAgain()
    await b.sync()
    #expect(await b.state == .cloudDeleted)
    #expect(try b.store.liveEntryCount() == 1)
    #expect(try b.store.syncState(.zoneGeneration) == nil || b.store.syncState(.zoneGeneration) != rig.cloud.generation("alice"))
}

// MARK: Account

@Test func iCloudOffKeepsQueueingAndPushesWhenBack() async throws {
    let rig = Rig()
    let a = try await rig.device()
    try a.capture("run")
    await a.sync()
    a.link.user = nil
    let walk = try a.capture("walk")
    await a.sync()
    #expect(await a.state == .iCloudOff)
    #expect(try a.store.pendingRecordCount() > 0)
    a.link.user = "alice"
    await a.sync()
    #expect(isSynced(await a.state))
    #expect(rig.cloud.records("alice")[walk] != nil)
}

@Test func switchToAnAccountWithoutTheZoneMergesSilently() async throws {
    let rig = Rig()
    let a = try await rig.device()
    let run = try a.capture("run")
    await a.sync()
    a.link.user = "bob"
    await a.sync()
    #expect(isSynced(await a.state))
    #expect(try a.store.syncState(.cloudUser) == "bob")
    #expect(rig.cloud.zone("bob") != nil && rig.cloud.records("bob")[run] != nil)
    #expect(rig.cloud.generation("bob") != rig.cloud.generation("alice"))
    // System fields of alice's zone were cleared, not sent to bob's (no conflicts or unknown items).
    let meta = try #require(try a.store.cloudMeta([run])[run])
    #expect(String(decoding: meta, as: UTF8.self).hasPrefix("\(rig.cloud.zone("bob")!.epoch):"))
}

@Test func activateCloudClearsMetaAndMarksAllPending() async throws {
    let rig = Rig()
    let a = try await rig.device()
    let run = try a.capture("run")
    await a.sync()
    #expect(try a.store.pendingRecordCount() == 0 && !a.store.cloudMeta([run]).isEmpty)
    try a.store.activateCloud(user: "bob")
    #expect(try a.store.cloudMeta([run]).isEmpty)
    #expect(try a.store.syncState(.changeToken) == nil && a.store.syncState(.zoneGeneration) == nil)
    #expect(try a.store.pendingPush().records.contains { $0.id == run })
}

// MARK: Saves

@Test func staleTagConflictMergesTheServerCopyAndResends() async throws {
    let rig = Rig()
    let a = try await rig.device("A"), b = try await rig.device("B")
    let run = try a.capture("run")
    await a.sync()
    await b.sync()
    rig.clock.ms += 1_000
    try a.store.setEntryNote(run, "from A")
    let fromA = try #require(try a.entry(run))
    rig.clock.ms += 1_000
    _ = try b.store.setEntryText(run, "running")
    // A's save lands between B's pull and B's push.
    rig.cloud.beforeNextSave { [cloud = rig.cloud] in cloud.inject(user: "alice", [fromA]) }
    await b.sync()
    #expect(isSynced(await b.state))
    let stored = try #require(rig.cloud.records("alice")[run])
    #expect(stored.fields["note"]?.value == .string("from A") && stored.fields["text"]?.value == .string("running"))
    #expect(try b.note(run) == "from A")
    #expect(try b.store.pendingRecordCount() == 0)
}

@Test func existingRecordWithoutLocalMetaIsAConflictThenSaved() async throws {
    let rig = Rig()
    let a = try await rig.device()
    let run = try a.capture("run")
    await a.sync()
    try a.store.dropCloudMeta([run])
    rig.clock.ms += 1_000
    try a.store.setEntryNote(run, "note")
    await a.sync()
    #expect(isSynced(await a.state))
    #expect(rig.cloud.records("alice")[run]?.fields["note"]?.value == .string("note"))
    #expect(try !a.store.cloudMeta([run]).isEmpty && a.store.pendingRecordCount() == 0)
}

@Test func retriedAndUnknownItemRecordsAreSentAgain() async throws {
    let rig = Rig()
    let a = try await rig.device()
    let run = try a.capture("run"), walk = try a.capture("walk")
    await a.sync()
    rig.clock.ms += 1_000
    try a.store.setEntryNote(run, "r")
    try a.store.setEntryNote(walk, "w")
    rig.cloud.script(run, .retry)
    rig.cloud.script(walk, .unknownItem)
    await a.sync()
    #expect(isSynced(await a.state))
    #expect(try a.store.pendingRecordCount() == 0)
    #expect(rig.cloud.records("alice")[run]?.fields["note"]?.value == .string("r"))
    #expect(rig.cloud.records("alice")[walk]?.fields["note"]?.value == .string("w"))
}

@Test func failedRecordIsExcludedAndTheRestIsSaved() async throws {
    let rig = Rig()
    let a = try await rig.device()
    let bad = try a.capture("run"), good = try a.capture("walk")
    rig.cloud.script(bad, .failed(.other("invalid")))
    await a.sync()
    #expect(isSynced(await a.state))
    #expect(rig.cloud.records("alice")[bad] == nil && rig.cloud.records("alice")[good] != nil)
    let saves = rig.cloud.count(.save)
    await a.sync()
    #expect(rig.cloud.count(.save) == saves, "the excluded record is not retried in this app version")
}

@Test func limitExceededHalvesTheBatch() async throws {
    let rig = Rig()
    let a = try await rig.device()
    try a.capture("run")
    try a.capture("walk")
    rig.cloud.fail(.save, with: .limitExceeded)
    await a.sync()
    #expect(isSynced(await a.state))
    let sizes = rig.cloud.batchSizes
    #expect(sizes.count >= 2 && sizes[1] < sizes[0])
    #expect(try a.store.pendingRecordCount() == 0)
}

// MARK: Pull

@Test func changeTokenExpiredRefetchesEverything() async throws {
    let rig = Rig()
    let a = try await rig.device("A"), b = try await rig.device("B")
    let run = try a.capture("run")
    await a.sync()
    await b.sync()
    let walk = try a.capture("walk")
    await a.sync()
    rig.cloud.fail(.fetchChanges, with: .changeTokenExpired)
    let fetches = rig.cloud.count(.fetchChanges)
    await b.sync()
    #expect(isSynced(await b.state))
    #expect(rig.cloud.count(.fetchChanges) >= fetches + 2)
    #expect(try b.entry(run) != nil && b.entry(walk) != nil)
}

@Test func pagesFollowThePageLimit() async throws {
    let rig = Rig()
    let a = try await rig.device("A"), b = try await rig.device("B")
    for w in ["run", "walk", "swim"] { try a.capture(w, translation: w) }
    await a.sync()
    rig.cloud.pageLimit = 2
    let fetches = rig.cloud.count(.fetchChanges)
    await b.sync()
    #expect(try b.store.liveEntryCount() == 3)
    #expect(rig.cloud.count(.fetchChanges) - fetches > 3)
}

// MARK: Cloud purge

@Test func savedEntryTombstoneDeletesTheGroupChildrenFromTheCloud() async throws {
    let rig = Rig()
    let a = try await rig.device("A"), b = try await rig.device("B")
    let run = try a.capture("run", translation: "бежать")
    await a.sync()
    await b.sync()
    #expect(try b.count("sense") == 1)
    let children = rig.cloud.records("alice").values.filter { $0.owner == run }.map(\.id)
    #expect(!children.isEmpty)

    try a.store.deleteEntries([run])
    #expect(try a.count("sense") == 1, "children stay until the tombstone is saved")
    await a.sync()
    let cloud = rig.cloud.records("alice")
    #expect(cloud[run]?.deleted == true)
    #expect(children.allSatisfy { cloud[$0] == nil })
    #expect(try a.count("sense") == 0 && a.store.pendingRecordCount() == 0)

    await b.sync()
    #expect(try b.count("sense") == 0 && b.count("card") == 0)
    #expect(try b.entry(run)?.deleted == true)
}

@Test func liveChildrenOfADeletedEntryArePurgedOnSight() async throws {
    let rig = Rig()
    let a = try await rig.device("A")
    let run = try a.capture("run", translation: "бежать")
    let records = try JSONDecoder().decode(Backup.self, from: a.store.exportBackup(attribution: "")).records
    var tombstone = try #require(records.first { $0.id == run })
    tombstone.deleted = true
    tombstone.fields = [:]
    let children = records.filter { $0.owner == run }
    rig.cloud.inject(user: "alice", [tombstone] + children)

    let b = try await rig.device("B")
    await b.sync()
    #expect(isSynced(await b.state))
    #expect(try b.count("sense") == 0)
    #expect(children.allSatisfy { rig.cloud.records("alice")[$0.id] == nil })
    #expect(rig.cloud.records("alice")[run]?.deleted == true)
}

// MARK: Errors

@Test func offlineWaitsForNetworkWithBackoff() async throws {
    let rig = Rig()
    let a = try await rig.device()
    await a.sync()
    a.link.online = false
    await a.sync()
    #expect(await a.state == .waitingForNetwork)
    await a.sync()
    try await Task.sleep(for: .milliseconds(20))
    #expect(rig.sleeps.all.suffix(2) == [5_000, 10_000])
    a.link.online = true
    await a.engine.networkPathChanged(satisfied: true)
    #expect(isSynced(await a.state))
}

@Test func rateLimitKeepsTheLastStateAndRetriesAfterTheCloudDelay() async throws {
    let rig = Rig()
    let a = try await rig.device()
    await a.sync()
    rig.cloud.fail(.fetchChanges, with: .rateLimited(retryAfter: 30))
    await a.sync()
    #expect(isSynced(await a.state))
    try await Task.sleep(for: .milliseconds(20))
    #expect(rig.sleeps.all.last == 30_000)
}

@Test func quotaAndAuthenticationErrorsMapToTheirStates() async throws {
    let rig = Rig()
    let a = try await rig.device()
    try a.capture("run")
    rig.cloud.fail(.save, with: .quotaExceeded)
    await a.sync()
    #expect(await a.state == .quotaFull)
    #expect(await a.engine.status.syncNowEnabled)
    rig.cloud.fail(.fetchChanges, with: .notAuthenticated)
    await a.sync()
    #expect(await a.state == .iCloudOff)
    await a.sync()
    #expect(isSynced(await a.state))
}

@Test func deviceClockFarFromTheCloudWarnsWithoutBlocking() async throws {
    let rig = Rig()
    let a = try await rig.device(offsetMs: 2 * HLCState.hourMs)
    try a.capture("run")
    await a.sync()
    #expect(isSynced(await a.state))
    #expect(await a.engine.status.clockWarning)
}
