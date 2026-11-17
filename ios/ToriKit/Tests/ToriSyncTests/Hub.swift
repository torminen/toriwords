import Foundation
import ToriCore
@testable import ToriSync

/// In-memory backend for tests: the server side of doc 36 §21 (envelope merge only, per-user `seq` cursor,
/// merge-group purge, validation) plus the session rules of §19.3/§20.4 that the client depends on.
/// Google `idToken` / Apple `identityToken` = `"acct:<name>"`.
final class Hub: @unchecked Sendable {
    static let knownTypes: Set<String> = ["language_pair", "entry", "sense", "context", "source", "card", "review_log", "tag",
                                          "entry_tag", "settings", "device"]

    struct Stored {
        var record: SyncRecord
        var seq: Int
    }

    final class Account {
        let id: String
        var seq = 0
        var records: [ToriID: Stored] = [:]
        /// Entries of purged merge groups (§21.4).
        var purged: Set<ToriID> = []
        var deleted = false
        init(id: String) { self.id = id }
    }

    struct SessionRow {
        var account: String
        var sessionId: String
        var deviceId: String
        var access: String
        var accessExpires: Int64
        var refresh: String
        var family: String
        var revoked: String?
    }

    private let lock = NSLock()
    let now: @Sendable () -> Int64
    private(set) var accounts: [String: Account] = [:]
    private var accountByName: [String: String] = [:]
    private var sessions: [String: SessionRow] = [:]  // by sessionId
    private var refreshHistory: [String: String] = [:]  // old refresh token -> family
    private var counter = 0
    /// Highest schema the server knows per type (`upgradeSchema` raises it).
    var knownSchema: [String: Int] = [:]
    var extraTypes: Set<String> = []
    private(set) var log: [HTTPRequest] = []
    /// Status overrides for the next requests to a path (error-path tests).
    var scripted: [String: [HTTPResponse]] = [:]
    var accessLifetimeMs: Int64 = 3_600_000

    init(now: @escaping @Sendable () -> Int64) { self.now = now }

    func account(named name: String) -> Account? { lock.withLock { accountByName[name].flatMap { accounts[$0] } } }
    func requests(_ path: String) -> [HTTPRequest] { lock.withLock { log.filter { $0.path == path } } }

    /// A newer client wrote these records (`upgradeSchema`): merged like a push, no validation.
    func inject(account name: String, _ records: [SyncRecord]) {
        lock.withLock {
            guard let acc = accountByName[name].flatMap({ accounts[$0] }) else { return }
            for r in records {
                extraTypes.insert(r.type)
                knownSchema[r.type] = max(knownSchema[r.type] ?? 1, r.schema)
            }
            merge(acc, records)
        }
    }

    // MARK: Transport

    func handle(_ r: HTTPRequest) -> HTTPResponse {
        lock.withLock {
            log.append(r)
            if var queue = scripted[r.path], !queue.isEmpty {
                let next = queue.removeFirst()
                scripted[r.path] = queue
                return dated(next)
            }
            guard r.headers["Toriwords-Protocol"] == "1", r.headers["Toriwords-Client"]?.hasPrefix("ios/") == true else {
                return error(426, "upgrade_required")
            }
            switch (r.method, r.path) {
            case ("POST", "/auth/google"), ("POST", "/auth/apple"): return signIn(r)
            case ("POST", "/auth/refresh"): return refresh(r)
            default: break
            }
            let auth = authorize(r)
            guard case .success(let sessionId) = auth else {
                if case .failure(let resp) = auth { return resp }
                return error(401, "session_revoked")
            }
            let session = sessions[sessionId]!
            let acc = accounts[session.account]!
            switch (r.method, r.path) {
            case ("POST", "/auth/logout"):
                sessions[sessionId]?.revoked = "logout"
                return dated(HTTPResponse(status: 204))
            case ("DELETE", "/account"):
                acc.deleted = true
                acc.records = [:]
                accountByName = accountByName.filter { $0.value != acc.id }
                for (id, s) in sessions where s.account == acc.id { sessions[id]?.revoked = "account_deleted" }
                return dated(HTTPResponse(status: 204))
            case ("GET", "/account"):
                return json(200, ["accountId": acc.id, "recordCount": acc.records.count])
            case ("POST", "/sync/push"): return push(acc, r)
            case ("GET", "/sync/pull"): return pull(acc, r)
            default: return error(404, "not_found")
            }
        }
    }

    private enum Auth { case success(String), failure(HTTPResponse) }

    private func authorize(_ r: HTTPRequest) -> Auth {
        guard let header = r.headers["Authorization"], header.hasPrefix("Bearer "),
              let s = sessions.values.first(where: { $0.access == String(header.dropFirst(7)) }) else {
            return .failure(error(401, "session_revoked"))
        }
        if s.revoked == "account_deleted" { return .failure(error(410, "account_deleted")) }
        if s.revoked != nil { return .failure(error(401, "session_revoked")) }
        if s.accessExpires <= now() { return .failure(error(401, "token_expired")) }
        return .success(s.sessionId)
    }

    private func token(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }

    private func signIn(_ r: HTTPRequest) -> HTTPResponse {
        let body = (try? JSONSerialization.jsonObject(with: r.body ?? Data())) as? [String: Any] ?? [:]
        guard let tokenValue = (body["idToken"] ?? body["identityToken"]) as? String, tokenValue.hasPrefix("acct:"),
              let device = body["deviceId"] as? String else { return error(400, "invalid_token") }
        let name = String(tokenValue.dropFirst(5))
        let accountId: String
        if let existing = accountByName[name] {
            accountId = existing
        } else {
            accountId = accounts[name] == nil ? name : token(name)
            accounts[accountId] = Account(id: accountId)
            accountByName[name] = accountId
        }
        for (id, s) in sessions where s.deviceId == device && s.revoked == nil { sessions[id]?.revoked = "replaced" }
        let s = SessionRow(account: accountId, sessionId: token("session"), deviceId: device, access: token("access"),
                           accessExpires: now() + accessLifetimeMs, refresh: token("refresh"), family: token("family"))
        sessions[s.sessionId] = s
        return sessionResponse(s, provider: r.path == "/auth/apple" ? "apple" : "google")
    }

    private func refresh(_ r: HTTPRequest) -> HTTPResponse {
        let body = (try? JSONSerialization.jsonObject(with: r.body ?? Data())) as? [String: Any] ?? [:]
        let presented = body["refreshToken"] as? String ?? ""
        guard var s = sessions.values.first(where: { $0.refresh == presented }) else {
            if let family = refreshHistory[presented] {
                for (id, s) in sessions where s.family == family { sessions[id]?.revoked = "reuse_detected" }
            }
            return error(401, "session_revoked")
        }
        if s.revoked == "account_deleted" { return error(410, "account_deleted") }
        if s.revoked != nil { return error(401, "session_revoked") }
        refreshHistory[s.refresh] = s.family
        s.refresh = token("refresh")
        s.access = token("access")
        s.accessExpires = now() + accessLifetimeMs
        sessions[s.sessionId] = s
        return sessionResponse(s, provider: "google")
    }

    private func sessionResponse(_ s: SessionRow, provider: String) -> HTTPResponse {
        json(200, ["accountId": s.account, "sessionId": s.sessionId, "provider": provider, "accessToken": s.access,
                   "accessTokenExpiresAt": ISO8601.format(Date(timeIntervalSince1970: Double(s.accessExpires) / 1000)),
                   "refreshToken": s.refresh])
    }

    // MARK: Sync (§21.2–§21.4)

    private func push(_ acc: Account, _ r: HTTPRequest) -> HTTPResponse {
        struct Body: Decodable { var deviceId: String; var records: [SyncRecord] }
        guard let body = try? APIClient.decoder.decode(Body.self, from: r.body ?? Data()) else { return error(400, "invalid_record") }
        guard body.records.count <= 500 else { return error(400, "too_large") }
        var invalid: [ToriID] = [], skewed: [ToriID] = []
        for rec in body.records {
            let stored = acc.records[rec.id]?.record
            if !(Self.knownTypes.contains(rec.type) || extraTypes.contains(rec.type)) || rec.schema > (knownSchema[rec.type] ?? 1)
                || (stored != nil && (stored!.type != rec.type || (rec.owner != nil && stored!.owner != rec.owner))) {
                invalid.append(rec.id)
            }
            if rec.fields.values.contains(where: { !HLCState.serverAccepts($0.clock, serverTime: now()) }) { skewed.append(rec.id) }
        }
        if !invalid.isEmpty { return error(400, "invalid_record", extra: ["recordIds": invalid.map(\.description)]) }
        if !skewed.isEmpty {
            return error(400, "clock_skew", extra: ["recordIds": skewed.map(\.description),
                                                    "serverTime": ISO8601.format(Date(timeIntervalSince1970: Double(now()) / 1000))])
        }
        merge(acc, body.records)
        return json(200, ["acked": body.records.map(\.id.description)])
    }

    private func merge(_ acc: Account, _ records: [SyncRecord]) {
        var changedEntries: [ToriID] = []
        for var rec in records {
            // §21.4 step 3: payloads into a purged group are acknowledged and discarded; the envelope still merges.
            if acc.purged.contains(rec.id) || rec.owner.map(acc.purged.contains) == true { rec.fields = [:] }
            let old = acc.records[rec.id]?.record
            let merged = old.map { SyncRecord.merge(local: $0, remote: rec) } ?? rec
            guard merged != old else { continue }
            acc.seq += 1
            acc.records[rec.id] = Stored(record: merged, seq: acc.seq)
            if merged.type == "entry", old == nil || old!.deleted != merged.deleted || old!.mergedInto != merged.mergedInto {
                changedEntries.append(rec.id)
            }
        }
        for id in changedEntries { purgeGroup(acc, of: id) }
    }

    private func root(_ acc: Account, _ id: ToriID) -> ToriID {
        var cur = id
        for _ in 0..<64 { guard let next = acc.records[cur]?.record.mergedInto else { break }; cur = next }
        return cur
    }

    private func purgeGroup(_ acc: Account, of id: ToriID) {
        let r = root(acc, id)
        let group = Set(acc.records.values.filter { $0.record.type == "entry" && root(acc, $0.record.id) == r }.map(\.record.id))
        guard group.contains(where: { acc.records[$0]?.record.deleted == true }) else { return }
        acc.purged.formUnion(group)
        for (rid, stored) in acc.records where group.contains(rid) || stored.record.owner.map(group.contains) == true {
            acc.records[rid]?.record.fields = [:]  // no new seq (§21.4 step 4)
        }
    }

    private func pull(_ acc: Account, _ r: HTTPRequest) -> HTTPResponse {
        func q(_ n: String) -> String? { r.query.first { $0.name == n }?.value }
        let since = Int(q("since") ?? "0") ?? 0
        let limit = min(Int(q("limit") ?? "1000") ?? 1000, 1000)
        let types = q("types").map { Set($0.split(separator: ",").map(String.init)) }
        let all = acc.records.values.filter { $0.seq > since && (types?.contains($0.record.type) ?? true) }.sorted { $0.seq < $1.seq }
        let page = Array(all.prefix(limit))
        let body = PullPage(records: page.map(\.record), cursor: String(page.last?.seq ?? since), hasMore: all.count > limit)
        return dated(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"],
                                  body: try! APIClient.encoder.encode(body)))
    }

    // MARK: Responses

    private func dated(_ r: HTTPResponse) -> HTTPResponse {
        var r = r
        if r.headers["date"] == nil { r.headers["date"] = HTTPDate.format(unixMs: now()) }
        return r
    }

    private func json(_ status: Int, _ body: [String: Any]) -> HTTPResponse {
        dated(HTTPResponse(status: status, headers: ["Content-Type": "application/json"],
                           body: try! JSONSerialization.data(withJSONObject: body)))
    }

    private func error(_ status: Int, _ code: String, extra: [String: Any] = [:]) -> HTTPResponse {
        json(status, extra.merging(["error": code, "message": code]) { a, _ in a })
    }
}

/// One device's connection to the hub; `online = false` behaves like no network path.
final class HubLink: HTTPTransport, @unchecked Sendable {
    let hub: Hub
    private let lock = NSLock()
    private var _online = true
    var online: Bool {
        get { lock.withLock { _online } }
        set { lock.withLock { _online = newValue } }
    }

    init(_ hub: Hub) { self.hub = hub }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard online else { throw TransportError.offline }
        return hub.handle(request)
    }
}
