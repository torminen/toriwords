import Foundation
import Testing
import ToriCore
@testable import ToriStore
@testable import ToriSync

/// Records requests and answers from a queue (or one fixed response).
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<HTTPResponse, TransportError>]
    private(set) var sent: [HTTPRequest] = []
    let delayMs: Int

    init(_ responses: [Result<HTTPResponse, TransportError>], delayMs: Int = 0) {
        queue = responses
        self.delayMs = delayMs
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let next: Result<HTTPResponse, TransportError> = lock.withLock {
            sent.append(request)
            return queue.count > 1 ? queue.removeFirst() : queue[0]
        }
        if delayMs > 0 { try await Task.sleep(for: .milliseconds(delayMs)) }
        return try next.get()
    }

    var requests: [HTTPRequest] { lock.withLock { sent } }
}

func response(_ status: Int, _ body: [String: Any] = [:], headers: [String: String] = [:]) -> Result<HTTPResponse, TransportError> {
    .success(HTTPResponse(status: status, headers: headers, body: try! JSONSerialization.data(withJSONObject: body)))
}

nonisolated(unsafe) let sessionBody: [String: Any] = ["accountId": "acc", "sessionId": "s1", "provider": "google", "accessToken": "a2",
                                  "accessTokenExpiresAt": "2030-01-01T00:00:00.000Z", "refreshToken": "r2"]

// MARK: API client

@Test func clientSendsProtocolHeadersAndBearer() async throws {
    let t = FakeTransport([response(200, ["records": [], "cursor": "7", "hasMore": false])])
    let api = APIClient(transport: t, appVersion: "1.2.3", deviceID: ToriID.settings)
    let page = try await api.pull(since: "5", limit: 10, types: ["entry", "sense"], accessToken: "tok").value
    #expect(page.cursor == "7")
    let r = try #require(t.requests.first)
    #expect(r.method == "GET" && r.path == "/sync/pull")
    #expect(r.headers["Toriwords-Client"] == "ios/1.2.3")
    #expect(r.headers["Toriwords-Protocol"] == "1")
    #expect(r.headers["Authorization"] == "Bearer tok")
    #expect(r.headers["Accept-Encoding"] == "gzip")
    #expect(r.query.map { "\($0.name)=\($0.value ?? "")" } == ["since=5", "limit=10", "types=entry,sense"])
}

struct ErrorCase: Sendable, CustomTestStringConvertible {
    var status: Int
    var body: [String: String]
    var headers: [String: String] = [:]
    var expected: APIError
    var testDescription: String { "\(status) \(body["error"] ?? "-")" }
}

@Test(arguments: [
    ErrorCase(status: 400, body: ["error": "invalid_record"], expected: .invalidRecord(recordIDs: [])),
    ErrorCase(status: 400, body: ["error": "too_large"], expected: .tooLarge(recordIDs: [])),
    ErrorCase(status: 400, body: ["error": "invalid_token"], expected: .invalidToken),
    ErrorCase(status: 400, body: ["error": "invalid_code"], expected: .invalidCode),
    ErrorCase(status: 401, body: ["error": "token_expired"], expected: .tokenExpired),
    ErrorCase(status: 401, body: ["error": "session_revoked"], expected: .sessionRevoked),
    ErrorCase(status: 401, body: [:], expected: .sessionRevoked),
    ErrorCase(status: 410, body: ["error": "account_deleted"], expected: .accountDeleted),
    ErrorCase(status: 426, body: ["error": "upgrade_required"], expected: .upgradeRequired),
    ErrorCase(status: 429, body: ["error": "rate_limited"], headers: ["retry-after": "17"], expected: .rateLimited(retryAfter: 17)),
    ErrorCase(status: 429, body: [:], expected: .rateLimited(retryAfter: 60)),
    ErrorCase(status: 503, body: [:], expected: .unreachable),
    ErrorCase(status: 418, body: ["error": "teapot"], expected: .unexpected(status: 418, code: "teapot")),
])
func clientMapsErrors(_ c: ErrorCase) async {
    let t = FakeTransport([response(c.status, c.body, headers: c.headers)])
    let api = APIClient(transport: t, appVersion: "1", deviceID: ToriID.settings)
    await #expect(throws: c.expected) { try await api.logout(accessToken: "x") }
}

@Test func clientMapsRecordIDsAndClockSkew() async {
    let id = ToriID.settings
    let t = FakeTransport([response(400, ["error": "clock_skew", "recordIds": [id.description],
                                          "serverTime": "2025-11-10T12:00:00.250Z"])])
    let api = APIClient(transport: t, appVersion: "1", deviceID: id)
    await #expect(throws: APIError.clockSkew(serverTime: 1_762_776_000_250, recordIDs: [id])) {
        _ = try await api.push([], accessToken: "x")
    }
}

@Test func clientMapsTransportFailures() async {
    for (failure, expected) in [(TransportError.offline, APIError.offline), (.unreachable, .unreachable)] {
        let api = APIClient(transport: FakeTransport([.failure(failure)]), appVersion: "1", deviceID: ToriID.settings)
        await #expect(throws: expected) { try await api.logout(accessToken: "x") }
    }
}

@Test func clientReportsServerTimeFromDateHeader() async throws {
    let seen = ScenarioClock(0)
    let t = FakeTransport([response(401, ["error": "session_revoked"], headers: ["date": "Mon, 10 Nov 2025 12:00:00 GMT"])])
    let api = APIClient(transport: t, appVersion: "1", deviceID: ToriID.settings) { seen.ms = $0 }
    _ = try? await api.logout(accessToken: "x")
    #expect(seen.ms == 1_762_776_000_000)
    #expect(HTTPDate.format(unixMs: 1_762_776_000_000) == "Mon, 10 Nov 2025 12:00:00 GMT")
}

// MARK: Sessions

func session(expiresAt: Int64 = 0) -> Session {
    Session(accountId: "acc", sessionId: "s1", accessToken: "a1", accessTokenExpiresAt: expiresAt, refreshToken: "r1")
}

@Test func concurrentRefreshesShareOneRequest() async throws {
    let t = FakeTransport([response(200, sessionBody)], delayMs: 50)
    let store = InMemorySessionStore(session())
    let manager = SessionManager(api: APIClient(transport: t, appVersion: "1", deviceID: ToriID.settings), store: store,
                                 now: { 0 })
    let tokens = try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<5 { group.addTask { try await manager.refresh().accessToken } }
        return try await group.reduce(into: []) { $0.append($1) }
    }
    #expect(tokens == Array(repeating: "a2", count: 5))
    #expect(t.requests.filter { $0.path == "/auth/refresh" }.count == 1)
    #expect(try store.load()?.refreshToken == "r2")
}

@Test func expiredTokenIsRefreshedAndTheCallRetriedOnce() async throws {
    let t = FakeTransport([response(401, ["error": "token_expired"]), response(200, sessionBody), response(200, [:])])
    let manager = SessionManager(api: APIClient(transport: t, appVersion: "1", deviceID: ToriID.settings),
                                 store: InMemorySessionStore(session(expiresAt: .max)), now: { 0 })
    let api = APIClient(transport: t, appVersion: "1", deviceID: ToriID.settings)
    try await manager.authorized { token in try await api.logout(accessToken: token) }
    #expect(t.requests.map(\.path) == ["/auth/logout", "/auth/refresh", "/auth/logout"])
    #expect(t.requests.last?.headers["Authorization"] == "Bearer a2")
}

@Test func revokedRefreshLosesTheSession() async throws {
    let lost = ScenarioClock(0)
    let store = InMemorySessionStore(session())
    let manager = SessionManager(api: APIClient(transport: FakeTransport([response(401, ["error": "session_revoked"])]),
                                                appVersion: "1", deviceID: ToriID.settings), store: store, now: { 0 })
    await manager.setLossHandler { _ in lost.ms += 1 }
    await #expect(throws: APIError.sessionRevoked) { try await manager.refresh() }
    #expect(lost.ms == 1)
    #expect(try store.load() == nil)
    #expect(await manager.current == nil)
}

@Test func networkErrorKeepsTheSession() async throws {
    let store = InMemorySessionStore(session())
    let manager = SessionManager(api: APIClient(transport: FakeTransport([.failure(.offline)]), appVersion: "1",
                                                deviceID: ToriID.settings), store: store, now: { 0 })
    await #expect(throws: APIError.offline) { try await manager.refresh() }
    #expect(try store.load() != nil)
}

// MARK: Backoff

@Test func backoffDoublesFromFiveSecondsToFifteenMinutes() {
    #expect((0..<10).map { Backoff.delayMs(attempt: $0, jitter: 0.5) }
            == [5_000, 10_000, 20_000, 40_000, 80_000, 160_000, 320_000, 640_000, 900_000, 900_000])
    #expect(Backoff.delayMs(attempt: 0, jitter: 0) == 4_000)
    #expect(Backoff.delayMs(attempt: 0, jitter: 1) == 6_000)
    #expect(Backoff.delayMs(attempt: 99, jitter: 1) == 1_080_000)
}

// MARK: Engine status machine and error paths (against the hub)

/// Captures the sleeps the engine schedules; never sleeps.
final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []
    func record(_ ms: Int64) { lock.withLock { values.append(ms) } }
    var all: [Int64] { lock.withLock { values } }
}

struct Rig {
    let hub: Hub
    let device: Device
    let sleeps = SleepLog()
    var engine: SyncEngine { device.engine }
    var store: ToriStore { device.store }

    init() async throws {
        let clock = ScenarioClock(1_762_776_000_000)
        hub = Hub { clock.ms }
        device = try await Device(name: "A", hub: hub, clock: clock, offsetMs: 0, sleep: { [sleeps] in
            sleeps.record($0)
            throw CancellationError()
        })
    }

    func capture(_ term: String) throws -> ToriID {
        try store.capture(CaptureInput(term: term, capturedAt: 1_762_776_000_000, senses: [], sentence: nil, source: nil, tags: []))
    }

    func signIn(_ account: String = "alice") async throws -> SignInResult {
        try await engine.signIn(.google(idToken: "acct:\(account)", nonce: nil))
    }

    func script(_ path: String, _ status: Int, _ body: [String: Any] = [:], headers: [String: String] = [:]) {
        hub.scripted[path, default: []].append(
            HTTPResponse(status: status, headers: headers, body: try! JSONSerialization.data(withJSONObject: body)))
    }
}

@Test func signInMovesFromLocalOnlyThroughFirstSyncToSynced() async throws {
    let rig = try await Rig()
    _ = try rig.capture("run")
    var states: [SyncState] = []
    let updates = await rig.engine.statusUpdates()
    let collector = Task {
        var seen: [SyncState] = []
        for await s in updates where seen.last != s.state {
            seen.append(s.state)
            if s.state == .synced { break }
        }
        return seen
    }
    #expect(try await rig.signIn() == .syncing)
    states = await collector.value
    #expect(states == [.localOnly, .firstSync, .synced])
    #expect(await rig.engine.status.notices == [.backedUp])
    #expect(await rig.engine.status.syncNowEnabled)
}

@Test func upgradeRequiredStopsSyncing() async throws {
    let rig = try await Rig()
    _ = try await rig.signIn()
    rig.script("/sync/push", 426, ["error": "upgrade_required"])
    _ = try rig.capture("run")
    await rig.engine.sync()
    #expect(await rig.engine.status.state == .updateRequired)
    let before = rig.hub.requests("/sync/pull").count
    await rig.engine.sync()
    #expect(rig.hub.requests("/sync/pull").count == before)
}

@Test func rateLimitKeepsSyncedAndRetriesAfterTheServerDelay() async throws {
    let rig = try await Rig()
    _ = try await rig.signIn()
    rig.script("/sync/pull", 429, ["error": "rate_limited"], headers: ["retry-after": "30"])
    await rig.engine.sync()
    #expect(await rig.engine.status.state == .synced)
    try await Task.sleep(for: .milliseconds(20))
    #expect(rig.sleeps.all.last == 30_000)
}

@Test func offlineWaitsForNetworkWithBackoff() async throws {
    let rig = try await Rig()
    _ = try await rig.signIn()
    rig.device.link.online = false
    await rig.engine.sync()
    #expect(await rig.engine.status.state == .waitingForNetwork)
    await rig.engine.sync()
    try await Task.sleep(for: .milliseconds(20))
    #expect(rig.sleeps.all.suffix(2) == [5_000, 10_000])
}

@Test func serverErrorIsUnreachable() async throws {
    let rig = try await Rig()
    _ = try await rig.signIn()
    rig.script("/sync/pull", 503)
    await rig.engine.sync()
    #expect(await rig.engine.status.state == .unreachable)
}

@Test func revokedSessionSignsOutAndKeepsWords() async throws {
    let rig = try await Rig()
    _ = try rig.capture("run")
    _ = try await rig.signIn()
    rig.script("/sync/pull", 401, ["error": "session_revoked"])
    await rig.engine.sync()
    #expect(await rig.engine.status.state == .localOnly)
    #expect(await rig.engine.status.notices.last == .signedOut)
    #expect(try rig.store.liveEntryCount() == 1)
    #expect(try rig.store.syncState(.accountId) == nil)
}

@Test func accountDeletedOnAnotherDeviceEndsTheSession() async throws {
    let rig = try await Rig()
    _ = try rig.capture("run")
    _ = try await rig.signIn()
    rig.script("/sync/pull", 410, ["error": "account_deleted"])
    await rig.engine.sync()
    #expect(await rig.engine.status.state == .localOnly)
    #expect(await rig.engine.status.notices.last == .accountDeletedElsewhere)
    #expect(try rig.store.liveEntryCount() == 1)
}

@Test(arguments: [false, true])
func deleteAccountGoesLocalOnly(removeLocalData: Bool) async throws {
    let rig = try await Rig()
    _ = try rig.capture("run")
    _ = try await rig.signIn()
    try await rig.engine.deleteAccount(removeLocalData: removeLocalData)
    #expect(await rig.engine.status.state == .localOnly)
    #expect(rig.hub.account(named: "alice") == nil)
    #expect(try rig.store.liveEntryCount() == (removeLocalData ? 0 : 1))
    #expect(await rig.engine.sessions.current == nil)
}

@Test func invalidRecordIsExcludedAndTheRestIsPushed() async throws {
    let rig = try await Rig()
    _ = try await rig.signIn()
    let bad = try rig.capture("run")
    _ = try rig.capture("walk")
    rig.script("/sync/push", 400, ["error": "invalid_record", "recordIds": [bad.description]])
    await rig.engine.sync()
    #expect(await rig.engine.status.state == .synced)
    let acc = try #require(rig.hub.account(named: "alice"))
    #expect(acc.records[bad] == nil)
    #expect(acc.records.values.contains { $0.record.type == "entry" })
    let pushedAfter = rig.hub.requests("/sync/push").count
    await rig.engine.sync()
    #expect(rig.hub.requests("/sync/push").count == pushedAfter, "the excluded record is not retried in this version")
}

@Test func tooLargeWithoutIDsHalvesTheBatch() async throws {
    let rig = try await Rig()
    _ = try await rig.signIn()
    _ = try rig.capture("run")
    rig.script("/sync/push", 400, ["error": "too_large"])
    await rig.engine.sync()
    let pushes = rig.hub.requests("/sync/push")
    struct Body: Decodable { var records: [SyncRecord] }
    let sizes = try pushes.suffix(2).map { try JSONDecoder().decode(Body.self, from: $0.body!).records.count }
    #expect(sizes[1] < sizes[0])
    #expect(await rig.engine.status.state == .synced)
}

@Test func signOutKeepsWordsAndLastSyncedAccount() async throws {
    let rig = try await Rig()
    _ = try rig.capture("run")
    _ = try await rig.signIn()
    try await rig.engine.signOut()
    #expect(await rig.engine.status.state == .localOnly)
    #expect(rig.hub.requests("/auth/logout").count == 1)
    #expect(try rig.store.syncState(.lastSyncedAccountId) == "alice")
    #expect(try rig.store.liveEntryCount() == 1)
}

// MARK: Sign-in helpers

@Test func pkceAndNonceHashes() {
    // Expected values from Python hashlib + base64.urlsafe_b64encode.
    #expect(AuthCrypto.pkceChallenge("dBjftJeZ4CVP-mJ92K9qFTiXcLGr8U1LSSn6t7-yIgM") == "ssIeg1EFqiPtAGsEjweW8zgfJRd0PvTiZvQKBDh9uwA")
    #expect(AuthCrypto.appleNonceHash("nonce-1") == "9e3f156324d42f0ea4b6f4fce81d56fbd64a2143a3fdd60a130d9c90e5b4d688")
    let token = AuthCrypto.randomToken()
    #expect(token.count == 43 && !token.contains(where: { "+/=".contains($0) }))
}

@Test func googleRedirectChecksState() throws {
    let config = GoogleOAuthConfig(clientID: "123.apps", redirectScheme: "com.googleusercontent.apps.123")
    let url = config.authorizationURL(state: "st", nonce: "n", codeChallenge: "ch")
    let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        .map { ($0.name, $0.value ?? "") })
    #expect(items["client_id"] == "123.apps" && items["code_challenge_method"] == "S256" && items["nonce"] == "n")
    #expect(items["redirect_uri"] == "com.googleusercontent.apps.123:/oauth2redirect")
    let ok = try #require(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?state=st&code=abc"))
    #expect(config.code(fromRedirect: ok, expectedState: "st") == "abc")
    #expect(config.code(fromRedirect: ok, expectedState: "other") == nil)
    let denied = try #require(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?state=st&error=access_denied"))
    #expect(config.code(fromRedirect: denied, expectedState: "st") == nil)
}
