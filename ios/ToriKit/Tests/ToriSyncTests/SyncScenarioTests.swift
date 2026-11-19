// TODO(step 2b, task 22): rewrite against InMemoryCloud; disabled while it targets the removed Hub/HTTP API.
#if false
import Foundation
import GRDB
import Testing
import ToriCore
import ToriTestSupport
@testable import ToriStore
@testable import ToriSync

/// `spec/fixtures/sync/`: the real ToriStore + SyncEngine for each simulated device, in-process, against `Hub`.
enum SyncScenarios {
    static var all: [FixtureCase] {
        let dir = FixtureLocator.url("sync")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.sorted().flatMap { Fixture.cases("sync/\($0)") }
    }
}

@Test(arguments: SyncScenarios.all)
func syncScenario(_ c: FixtureCase) async throws {
    let world = try await World(c)
    for (i, step) in c["steps"].array.enumerated() {
        try await world.run(step, index: i)
    }
    try await world.check(c["expected"])
}

final class ScenarioClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64
    init(_ v: Int64) { value = v }
    var ms: Int64 {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

final class Device {
    let name: String
    let store: ToriStore
    let engine: SyncEngine
    let link: HubLink
    let offset: ScenarioClock

    init(name: String, hub: Hub, clock: ScenarioClock, offsetMs: Int64,
         sleep: @escaping @Sendable (Int64) async throws -> Void = { _ in throw CancellationError() }) async throws {
        self.name = name
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let offset = ScenarioClock(offsetMs)
        self.offset = offset
        let now: @Sendable () -> Int64 = { clock.ms + offset.ms }
        store = try ToriStore(path: dir.appendingPathComponent("user.sqlite").path, now: now)
        try store.launch(deviceMarker: dir.appendingPathComponent("marker"), displayName: name, purgeKeychain: {})
        link = HubLink(hub)
        engine = SyncEngine(.init(store: store, transport: link, sessionStore: InMemorySessionStore(), appVersion: "1.0.0",
                                  deviceID: try store.thisDeviceID()!, now: now, sleep: sleep,
                                  jitter: { 0.5 }))
        try await engine.start()
    }
}

final class World {
    let c: FixtureCase
    let clock: ScenarioClock
    let start: Int64
    let hub: Hub
    var devices: [String: Device] = [:]
    /// Alias -> record ID (IDs are global across devices).
    var aliases: [String: ToriID] = [:]

    init(_ c: FixtureCase) async throws {
        self.c = c
        start = c["start"].int64!
        let clock = ScenarioClock(start)
        self.clock = clock
        hub = Hub(now: { clock.ms })
        for (name, cfg) in c["devices"].object.sorted(by: { $0.key < $1.key }) {
            devices[name] = try await Device(name: name, hub: hub, clock: clock, offsetMs: Int64(cfg["clockOffsetSec"].int ?? 0) * 1000)
        }
    }

    func entry(_ d: Device, _ alias: String) throws -> ToriID {
        let id = try #require(aliases[alias], "unknown alias \(alias)")
        return try d.store.db.read { try ToriID.fetchOne($0, sql: "SELECT canonical_id FROM entry WHERE id = ?", arguments: [id]) } ?? id
    }

    func run(_ s: JSON, index: Int) async throws {
        clock.ms = start + Int64(s["t"].int!) * 1000
        let op = s["op"].string!
        if op == "upgradeSchema" { return upgrade(s) }
        let d = try #require(devices[s["device"].string ?? ""], "step \(index): device")
        let store = d.store, engine = d.engine
        switch op {
        case "capture":
            let source = s["url"].string.map { SourceInput(kind: .web, url: $0, title: nil) }
            let id = try store.capture(CaptureInput(term: s["term"].string!, capturedAt: clock.ms + d.offset.ms,
                                                    senses: s["translations"].array.map { NewSense(translation: $0.string!) },
                                                    sentence: s["sentence"].string, source: source,
                                                    tags: s["tags"].array.map(\.string!)))
            if let alias = s["as"].string { aliases[alias] = id }
        case "editField":
            let id = try entry(d, s["entry"].string!)
            let value = s["value"].string
            switch s["field"].string! {
            case "text": _ = try store.setEntryText(id, value!)
            case "note": try store.setEntryNote(id, value)
            case "ipa": try store.setEntryIPA(id, value)
            case "translation":
                let sense = try #require(try store.read { try $0.entry(id) }?.senses.first, "step \(index): no sense")
                try store.editSense(sense.id, translation: value, definition: sense.definition, partOfSpeech: sense.partOfSpeech)
            default: Issue.record("step \(index): unknown field")
            }
        case "enrich":
            let id = try entry(d, s["entry"].string!)
            if let t = s["translation"].string { try store.fillAutomaticSense(id, NewSense(translation: t, source: .mtApple)) }
            if let ipa = s["ipa"].string { try store.setEntryIPA(id, ipa, rank: .automatic) }
        case "review":
            let id = try entry(d, s["entry"].string!)
            let dir = CardDirection(rawValue: s["direction"].string ?? "recognition")!
            let rating: Rating = s["rating"].string == "forgot" ? .forgot : .remembered
            try store.commitAnswer(card: .card(entry: id, direction: dir), rating: rating, reviewedAt: clock.ms + d.offset.ms,
                                   utcOffsetMin: 0, answerMs: 2000)
        case "exclude":
            try store.setStatus([try entry(d, s["entry"].string!)], s["reason"].string == "paused" ? .paused : .known)
        case "resume": try store.setStatus([try entry(d, s["entry"].string!)], .active)
        case "delete": try store.deleteEntries([try entry(d, s["entry"].string!)])
        case "tag": try store.tag([try entry(d, s["entry"].string!)], name: s["name"].string!)
        case "untag":
            let key = TextKey.tagKey(s["name"].string!)
            let tag = try #require(try store.read { try $0.allTags() }.first { TextKey.tagKey($0.name) == key }, "step \(index): tag")
            try store.untag(try entry(d, s["entry"].string!), tag: tag.id)
        case "mergeByEdit":
            #expect(try store.setEntryText(try entry(d, s["entry"].string!), s["text"].string!, mergeIfDuplicate: true) == .saved)
        case "setSettings":
            if let n = s["newWordsPerDay"].int { try store.setNewWordsPerDay(n) }
            if let r = s["desiredRetention"].double {
                var p = FSRSParameters.default
                p.desiredRetention = r
                try store.setSchedulerParameters(p, paramsID: "custom-\(Int(r * 100))")
            }
        case "signIn":
            let saved = await engine.pageLimit
            if let limit = s["limit"].int { await engine.setPageLimit(limit) }
            _ = try await engine.signIn(.google(idToken: "acct:" + s["account"].string!, nonce: nil))
            await engine.setPageLimit(saved)
        case "accountChoice":
            switch s["choice"].string! {
            case "add": _ = await engine.resolveAccountChoice(.add)
            case "remove": _ = await engine.resolveAccountChoice(.remove)
            default: break  // cancel: nothing to call
            }
        case "signOut": try await engine.signOut()
        case "deleteAccount": try await engine.deleteAccount(removeLocalData: s["removeLocal"].bool ?? false)
        case "network": d.link.online = s["online"].bool!
        case "setClock": d.offset.ms = Int64(s["offsetSec"].int!) * 1000
        case "sync", "pullOnly", "pushOnly":
            let saved = await engine.pageLimit
            if let limit = s["limit"].int { await engine.setPageLimit(limit) }
            await engine.cycle(push: op != "pullOnly", pull: op != "pushOnly")
            await engine.setPageLimit(saved)
        default: Issue.record("step \(index): unknown op \(op)")
        }
    }

    /// A newer client wrote raw records to the account (unknown fields / types, newer schema).
    func upgrade(_ s: JSON) {
        let clockValue = HLCTimestamp(ms: clock.ms, counter: 0, node: 0xfeed_face_cafe_beef)
        let records: [SyncRecord] = s["records"].array.map { r in
            let idText = r["id"].string!
            let id = aliases[idText] ?? ToriID(idText)!
            let fields = r["fields"].object.mapValues { f in
                FieldVersion(value: wire(f["v"]), clock: clockValue, rank: AuthorRank(rawValue: f["u"].int ?? 1)!)
            }
            return SyncRecord(id: id, type: r["type"].string!, schema: r["schema"].int ?? 1,
                              owner: r["owner"].string.flatMap { aliases[$0] ?? ToriID($0) }, deleted: false, mergedInto: nil,
                              fields: fields)
        }
        hub.inject(account: s["account"].string!, records)
    }

    func wire(_ j: JSON) -> WireValue {
        switch j {
        case .null, .object: .null
        case .bool(let b): .bool(b)
        case .int(let i): .int(i)
        case .double(let d): .double(d)
        case .string(let s): .string(s)
        case .array(let a): .array(a.map(wire))
        }
    }

    // MARK: Expectations

    func check(_ e: JSON) async throws {
        for (name, exp) in e["devices"].object {
            let d = try #require(devices[name])
            try await checkDevice(d, exp)
        }
        for (name, exp) in e["hub"].object { try checkHub(name, exp) }
        let converged = e["converged"].array.compactMap { $0.string.flatMap { devices[$0] } }
        if let first = converged.first {
            let reference = try dump(first)
            for d in converged.dropFirst() {
                let other = try dump(d)
                #expect(other == reference, "\(d.name) differs from \(first.name): \(Set(other).symmetricDifference(reference).sorted())")
            }
        }
    }

    func checkDevice(_ d: Device, _ exp: JSON) async throws {
        let store = d.store
        if exp.has("words") {
            let ids = try liveEntries(store)
            var actual: [String: [String: JSON]] = [:]
            for id in ids { let w = try word(store, id); actual[w["text"]!.string!] = w }
            let expected = exp["words"].array
            #expect(Set(actual.keys) == Set(expected.map { $0["text"].string! }), "\(d.name): words")
            for w in expected {
                guard let a = actual[w["text"].string!] else { continue }
                for (k, v) in w.object { #expect(a[k] == v, "\(d.name): \(w["text"].string!).\(k)") }
            }
        }
        if exp.has("settings") {
            let (n, r) = try settings(store)
            if let e = exp["settings"]["newWordsPerDay"].int { #expect(n == e, "\(d.name): newWordsPerDay") }
            if let e = exp["settings"]["desiredRetention"].double { #expect(r == e, "\(d.name): desiredRetention") }
        }
        if exp.has("account") {
            let a = exp["account"]
            let status = await d.engine.status
            if let state = a["state"].string { #expect(stateName(status.state) == state, "\(d.name): state \(status.state)") }
            if a.has("signedIn") { #expect(try accountName(store.syncState(.accountId)) == a["signedIn"].string, "\(d.name): signedIn") }
            if a.has("lastSynced") {
                #expect(try accountName(store.syncState(.lastSyncedAccountId)) == a["lastSynced"].string, "\(d.name): lastSynced")
            }
            if let p = a["pendingChoice"].bool { #expect(try (store.syncState(.pendingAccountChoice) != nil) == p, "\(d.name): pendingChoice") }
            if let n = a["outbox"].int { #expect(try store.pendingRecordCount() == n, "\(d.name): outbox") }
        }
        if exp.has("notices") {
            let notices = await d.engine.status.notices.map(noticeName)
            #expect(notices == exp["notices"].array.map(\.string!), "\(d.name): notices")
        }
    }

    func liveEntries(_ store: ToriStore) throws -> [ToriID] {
        try store.db.read { try ToriID.fetchAll($0, sql: "SELECT id FROM entry WHERE deleted = 0 AND merged_into IS NULL") }
    }

    func settings(_ store: ToriStore) throws -> (Int?, Double?) {
        try store.db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM settings WHERE id = ?", arguments: [ToriID.settings])
            return (row?["new_words_per_day"], row?["desired_retention"])
        }
    }

    /// Hub account IDs are the account names (a re-created account would get a suffix).
    func accountName(_ id: String?) -> String? { id }

    func stateName(_ s: SyncState) -> String {
        switch s {
        case .localOnly: "localOnly"
        case .firstSync: "firstSync"
        case .syncing: "syncing"
        case .synced: "synced"
        case .waitingForNetwork: "waitingForNetwork"
        case .unreachable: "unreachable"
        case .clockSkew: "clockSkew"
        case .updateRequired: "updateRequired"
        case .paused: "paused"
        }
    }

    func noticeName(_ n: SyncNotice) -> String {
        switch n {
        case .accountPrompt(let w): "accountPrompt:\(w)"
        case .removeNeedsNetwork: "removeNeedsNetwork"
        case .signedOut: "signedOut"
        case .accountDeletedElsewhere: "accountDeletedElsewhere"
        case let .mergeSummary(a, b, c): "mergeSummary:\(a)/\(b)/\(c)"
        case .backedUp: "backedUp"
        }
    }

    /// The fixture's logical word projection (README "Expected state").
    func word(_ store: ToriStore, _ id: ToriID) throws -> [String: JSON] {
        let detail = try #require(try store.read { try $0.entry(id) })
        let extraText = try store.db.read { try String.fetchOne($0, sql: "SELECT extra FROM entry WHERE id = ?", arguments: [id]) }
        var extra: [String: JSON] = [:]
        if let extraText, let obj = try? JSONDecoder().decode([String: JSON].self, from: Data(extraText.utf8)) {
            extra = obj.mapValues { $0["v"] }
        }
        let reviews = try store.db.read {
            try Int.fetchOne($0, sql: """
                SELECT COUNT(*) FROM review_log r JOIN card c ON c.id = r.canonical_card_id
                WHERE c.canonical_entry_id = ? AND r.deleted = 0
                """, arguments: [id]) ?? 0
        }
        let status: String = switch detail.status { case .active: "active"; case .known: "known"; case .paused: "paused" }
        return [
            "text": .string(detail.text), "note": detail.note.map(JSON.string) ?? .null, "ipa": detail.ipa.map(JSON.string) ?? .null,
            "status": .string(status), "needsCheck": .bool(detail.needsCheck),
            "translations": .array(detail.senses.compactMap { $0.translation.map(JSON.string) }),
            "contexts": .array(detail.contexts.compactMap { $0.sentence.map(JSON.string) }),
            "tags": .array(detail.tags.map(\.name).sorted().map(JSON.string)), "reviews": .int(Int64(reviews)),
            "extra": .object(extra),
        ]
    }

    func checkHub(_ name: String, _ exp: JSON) throws {
        let acc = try #require(hub.account(named: name), "hub account \(name)")
        let records = acc.records.values.map(\.record)
        if exp.has("entries") {
            let entries = records.filter { $0.type == "entry" }
            #expect(entries.filter { !$0.deleted && $0.mergedInto == nil }.count == exp["entries"]["live"].int, "hub \(name): live")
            #expect(entries.filter(\.deleted).count == exp["entries"]["deleted"].int, "hub \(name): deleted")
            #expect(entries.filter { !$0.deleted && $0.mergedInto != nil }.count == exp["entries"]["merged"].int, "hub \(name): merged")
        }
        for alias in exp["purged"].array.map(\.string!) {
            let id = try #require(aliases[alias])
            for r in records where r.id == id || r.owner == id {
                #expect(r.fields.isEmpty, "hub \(name): \(r.type) of \(alias) not purged")
            }
        }
        for (type, n) in exp["types"].object {
            #expect(records.filter { $0.type == type }.count == n.int, "hub \(name): \(type) count")
        }
    }

    /// Synced and derived state of visible records (no device-local columns), for convergence checks. Children of a
    /// deleted Entry are hidden and purged "later", so when that happens may differ per device.
    func dump(_ d: Device) throws -> [String] {
        let local: Set<String> = ["is_this_device", "enrich_attempts"]
        var out: [String] = []
        for type in RecordType.all {
            let owner = type.ownerColumn.map { col in
                " AND NOT EXISTS (SELECT 1 FROM entry e WHERE e.deleted = 1 AND e.id IN (t.\(col), (SELECT canonical_id FROM entry x WHERE x.id = t.\(col))))"
            } ?? ""
            for row in try d.store.db.read({ try Row.fetchAll($0, sql: "SELECT * FROM \(type.name) t WHERE deleted = 0\(owner) ORDER BY id") }) {
                let cols = row.columnNames.sorted().filter { !local.contains($0) }
                out.append(type.name + " " + cols.map { "\($0)=\(row[$0] as DatabaseValue)" }.joined(separator: " "))
            }
        }
        return out
    }
}

extension SyncEngine {
    func setPageLimit(_ n: Int) { pageLimit = n }
}
#endif
