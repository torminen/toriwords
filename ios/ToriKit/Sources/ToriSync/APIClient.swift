import Foundation
import ToriCore

/// Session response of E1, E5, E6.
public struct SessionResponse: Codable, Sendable, Equatable {
    public var accountId: String
    public var sessionId: String
    public var provider: String
    public var accessToken: String
    public var accessTokenExpiresAt: Date
    public var refreshToken: String

    public init(accountId: String, sessionId: String, provider: String, accessToken: String, accessTokenExpiresAt: Date,
                refreshToken: String) {
        self.accountId = accountId
        self.sessionId = sessionId
        self.provider = provider
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
    }
}

/// E9 response.
public struct AccountInfo: Codable, Sendable, Equatable {
    public struct Identity: Codable, Sendable, Equatable {
        public var provider: String
        public var createdAt: String
    }
    public struct DeviceSession: Codable, Sendable, Equatable {
        public var sessionId: String
        public var deviceId: String
        public var platform: String
        public var client: String
        public var createdAt: String
        public var lastUsedAt: String
        public var current: Bool
    }
    public var accountId: String
    public var createdAt: String
    public var identities: [Identity]
    public var sessions: [DeviceSession]
    public var recordCount: Int
    public var storageBytes: Int
}

public struct PullPage: Codable, Sendable, Equatable {
    public var records: [SyncRecord]
    public var cursor: String
    public var hasMore: Bool

    public init(records: [SyncRecord], cursor: String, hasMore: Bool) {
        self.records = records
        self.cursor = cursor
        self.hasMore = hasMore
    }
}

/// Provider credential for E1 / E5.
public enum SignInCredential: Sendable, Equatable {
    case apple(identityToken: String, authorizationCode: String, rawNonce: String)
    case google(idToken: String, nonce: String?)
}

/// The API error contract mapped for the client.
public enum APIError: Error, Equatable, Sendable {
    case offline
    case unreachable
    case invalidRecord(recordIDs: [ToriID])
    /// `recordIDs` empty: the batch itself was over the limits.
    case tooLarge(recordIDs: [ToriID])
    /// `serverTime` Unix ms.
    case clockSkew(serverTime: Int64, recordIDs: [ToriID])
    case invalidToken
    case invalidCode
    case tokenExpired
    case sessionRevoked
    case accountDeleted
    case upgradeRequired
    /// `Retry-After` seconds (60 when absent).
    case rateLimited(retryAfter: Int)
    case unexpected(status: Int, code: String?)
}

/// A decoded response plus the server time from its `Date` header (Unix ms), for the device-time check and `lastServerTime`.
public struct APIResponse<T: Sendable>: Sendable {
    public var value: T
    public var serverTime: Int64?
}

/// Typed calls of E1, E5–E7, E9, E10, E12, E13 with the `Toriwords-*` headers.
public struct APIClient: Sendable {
    public static let protocolVersion = "1"

    let transport: any HTTPTransport
    /// `CFBundleShortVersionString`.
    public let appVersion: String
    public let deviceID: ToriID
    /// Observes the `Date` of every response that arrived (also error responses): device-time check.
    let onServerTime: @Sendable (Int64) async -> Void

    public init(transport: any HTTPTransport, appVersion: String, deviceID: ToriID,
                onServerTime: @escaping @Sendable (Int64) async -> Void = { _ in }) {
        self.transport = transport
        self.appVersion = appVersion
        self.deviceID = deviceID
        self.onServerTime = onServerTime
    }

    // MARK: Auth

    public func signIn(_ credential: SignInCredential) async throws -> APIResponse<SessionResponse> {
        switch credential {
        case let .apple(identityToken, authorizationCode, rawNonce):
            return try await call("POST", "/auth/apple", body: [
                "identityToken": identityToken, "authorizationCode": authorizationCode, "rawNonce": rawNonce,
                "deviceId": deviceID.description, "platform": "ios",
            ])
        case let .google(idToken, nonce):
            var body = ["idToken": idToken, "deviceId": deviceID.description, "platform": "ios"]
            body["nonce"] = nonce
            return try await call("POST", "/auth/google", body: body)
        }
    }

    public func refresh(refreshToken: String) async throws -> APIResponse<SessionResponse> {
        try await call("POST", "/auth/refresh", body: ["refreshToken": refreshToken])
    }

    public func logout(accessToken: String) async throws {
        let _: APIResponse<Empty> = try await call("POST", "/auth/logout", token: accessToken)
    }

    // MARK: Account

    public func account(accessToken: String) async throws -> APIResponse<AccountInfo> {
        try await call("GET", "/account", token: accessToken)
    }

    public func deleteAccount(accessToken: String) async throws {
        let _: APIResponse<Empty> = try await call("DELETE", "/account", token: accessToken)
    }

    // MARK: Sync

    struct PushBody: Encodable {
        var deviceId: String
        var records: [SyncRecord]
    }

    struct Acked: Decodable, Sendable { var acked: [ToriID] }

    public func push(_ records: [SyncRecord], accessToken: String) async throws -> APIResponse<Set<ToriID>> {
        let r: APIResponse<Acked> = try await call("POST", "/sync/push", token: accessToken,
                                                   body: PushBody(deviceId: deviceID.description, records: records))
        return APIResponse(value: Set(r.value.acked), serverTime: r.serverTime)
    }

    public func pull(since cursor: String, limit: Int = 1000, types: [String]? = nil, accessToken: String) async throws
        -> APIResponse<PullPage> {
        var query = [URLQueryItem(name: "since", value: cursor), URLQueryItem(name: "limit", value: String(limit))]
        if let types { query.append(URLQueryItem(name: "types", value: types.joined(separator: ","))) }
        return try await call("GET", "/sync/pull", query: query, token: accessToken)
    }

    // MARK: Plumbing

    struct Empty: Decodable, Sendable {}
    struct NoBody: Encodable {}

    struct ErrorBody: Decodable {
        var error: String
        var recordIds: [ToriID]?
        var serverTime: String?
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(ISO8601.format(date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = ISO8601.parse(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(s)") }
            return date
        }
        return d
    }()

    func call<T: Decodable & Sendable>(_ method: String, _ path: String, query: [URLQueryItem] = [], token: String? = nil,
                                       body: (some Encodable)? = NoBody?.none) async throws -> APIResponse<T> {
        var headers = [
            "Toriwords-Client": "ios/\(appVersion)", "Toriwords-Protocol": Self.protocolVersion, "Accept-Encoding": "gzip",
        ]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        var data: Data?
        if let body {
            data = try Self.encoder.encode(body)
            headers["Content-Type"] = "application/json"
        }
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(method: method, path: path, query: query, headers: headers, body: data))
        } catch TransportError.offline {
            throw APIError.offline
        } catch {
            throw APIError.unreachable
        }
        let serverTime = response.headers["date"].flatMap(HTTPDate.parse)
        if let serverTime { await onServerTime(serverTime) }
        guard (200..<300).contains(response.status) else { throw Self.error(response) }
        if T.self == Empty.self { return APIResponse(value: Empty() as! T, serverTime: serverTime) }
        do {
            return APIResponse(value: try Self.decoder.decode(T.self, from: response.body), serverTime: serverTime)
        } catch {
            throw APIError.unexpected(status: response.status, code: "undecodable")
        }
    }

    static func error(_ r: HTTPResponse) -> APIError {
        let body = try? decoder.decode(ErrorBody.self, from: r.body)
        let ids = body?.recordIds ?? []
        switch (r.status, body?.error) {
        case (400, "invalid_record"): return .invalidRecord(recordIDs: ids)
        case (400, "too_large"): return .tooLarge(recordIDs: ids)
        case (400, "clock_skew"):
            guard let t = body?.serverTime.flatMap(ISO8601.parse) else { return .unexpected(status: 400, code: "clock_skew") }
            return .clockSkew(serverTime: Int64((t.timeIntervalSince1970 * 1000).rounded()), recordIDs: ids)
        case (400, "invalid_token"): return .invalidToken
        case (400, "invalid_code"): return .invalidCode
        case (401, "token_expired"): return .tokenExpired
        case (401, _): return .sessionRevoked
        case (410, _): return .accountDeleted
        case (426, _): return .upgradeRequired
        case (429, _): return .rateLimited(retryAfter: r.headers["retry-after"].flatMap { Int($0) } ?? 60)
        case (500..., _): return .unreachable
        default: return .unexpected(status: r.status, code: body?.error)
        }
    }
}

/// ISO 8601 UTC with milliseconds (`2026-11-16T16:50:00.000Z`).
enum ISO8601 {
    static func format(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// RFC 9110 IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`) <-> Unix ms.
public enum HTTPDate {
    static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }

    public static func parse(_ s: String) -> Int64? {
        formatter().date(from: s).map { Int64($0.timeIntervalSince1970) * 1000 }
    }

    public static func format(unixMs: Int64) -> String {
        formatter().string(from: Date(timeIntervalSince1970: Double(unixMs / 1000)))
    }
}
