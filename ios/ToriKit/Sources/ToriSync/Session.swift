import Foundation
#if canImport(Security)
import Security
#endif

/// The tokens kept for the signed-in account (doc 36 §12.3). `provider` goes to `sync_state.lastProvider` instead.
public struct Session: Codable, Sendable, Equatable {
    public var accountId: String
    public var sessionId: String
    public var accessToken: String
    /// Unix ms.
    public var accessTokenExpiresAt: Int64
    public var refreshToken: String

    public init(accountId: String, sessionId: String, accessToken: String, accessTokenExpiresAt: Int64, refreshToken: String) {
        self.accountId = accountId
        self.sessionId = sessionId
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
    }

    init(_ r: SessionResponse) {
        self.init(accountId: r.accountId, sessionId: r.sessionId, accessToken: r.accessToken,
                  accessTokenExpiresAt: Int64((r.accessTokenExpiresAt.timeIntervalSince1970 * 1000).rounded()),
                  refreshToken: r.refreshToken)
    }
}

/// Token storage seam: Keychain in the app, memory in tests.
public protocol SessionStore: Sendable {
    func load() throws -> Session?
    func save(_ session: Session) throws
    func clear() throws
}

public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: Session?

    public init(_ session: Session? = nil) { self.session = session }
    public func load() throws -> Session? { lock.withLock { session } }
    public func save(_ session: Session) throws { lock.withLock { self.session = session } }
    public func clear() throws { lock.withLock { session = nil } }
}

#if canImport(Security)
/// One generic-password item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not shared with extensions (§12.3).
public struct KeychainSessionStore: SessionStore {
    public enum KeychainError: Error { case status(OSStatus) }

    let service: String
    let account = "session"

    public init(service: String) { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() throws -> Session? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError.status(status) }
        return try JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError.status(update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
#endif

/// Why the session ended without the user signing out.
public enum SessionLoss: Sendable, Equatable {
    /// `session_revoked` or an unfixable 401: "You were signed out. Sign in again to continue syncing."
    case revoked
    /// `410 account_deleted`: "Your ToriWords account was deleted on another device. Your words stay on this device only."
    case accountDeleted
}

/// Owns the tokens: sign-in calls, single-flight refresh, authorized calls with one retry on `token_expired` (§12.3).
/// Session loss clears the tokens and reports to `onLoss`; local state is the caller's job.
public actor SessionManager {
    let api: APIClient
    let store: any SessionStore
    let now: @Sendable () -> Int64
    private var session: Session?
    private var refreshing: Task<Session, any Error>?
    /// Set by a successful refresh; `foregroundEnded()` resets it (pre-resolution check reuse, §12.3).
    private(set) var refreshedThisForeground = false
    private var onLoss: (@Sendable (SessionLoss) async -> Void)?

    public init(api: APIClient, store: any SessionStore, now: @escaping @Sendable () -> Int64) {
        self.api = api
        self.store = store
        self.now = now
        session = try? store.load()
    }

    public func setLossHandler(_ handler: @escaping @Sendable (SessionLoss) async -> Void) { onLoss = handler }

    public var current: Session? { session }

    /// E1 / E5. The session is **not** persisted here: the post-sign-in flow decides the order (§12.4).
    public func signIn(_ credential: SignInCredential) async throws -> SessionResponse {
        try await api.signIn(credential).value
    }

    public func persist(_ s: Session) throws {
        try store.save(s)
        session = s
    }

    /// Drops the tokens locally (sign-out, deletion, loss). No network call.
    public func discard() {
        refreshing?.cancel()
        refreshing = nil
        session = nil
        try? store.clear()
    }

    public func foregroundEnded() { refreshedThisForeground = false }

    /// Single-flight `POST /auth/refresh`: concurrent callers await the same request.
    @discardableResult
    public func refresh() async throws -> Session {
        if let refreshing { return try await refreshing.value }
        guard let s = session else { throw APIError.sessionRevoked }
        let task = Task { [api] in Session(try await api.refresh(refreshToken: s.refreshToken).value) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            guard session?.sessionId == s.sessionId || session?.accountId == s.accountId else { throw APIError.sessionRevoked }
            try persist(fresh)
            refreshedThisForeground = true
            return fresh
        } catch let e as APIError {
            if e == .sessionRevoked || e == .accountDeleted || e == .tokenExpired { await lose(e) }
            throw e
        }
    }

    /// Foreground check (§12.3): refresh if the access token expires within 5 minutes. Network errors are ignored.
    public func foregroundCheck() async {
        guard let s = session, s.accessTokenExpiresAt - now() < 5 * 60_000 else { return }
        _ = try? await refresh()
    }

    /// Pre-resolution check (§12.5): a valid session, reusing a refresh from this foreground.
    /// Throws `APIError.offline`/`.unreachable` on network errors, `.sessionRevoked`/`.accountDeleted` after loss.
    public func validate() async throws {
        if refreshedThisForeground, session != nil { return }
        try await refresh()
    }

    /// Runs `call` with a valid access token; on `token_expired` refreshes once and retries; loss errors end the session.
    public func authorized<T: Sendable>(_ call: @Sendable (String) async throws -> T) async throws -> T {
        guard var s = session else { throw APIError.sessionRevoked }
        if s.accessTokenExpiresAt <= now() { s = try await refresh() }
        do {
            return try await call(s.accessToken)
        } catch APIError.tokenExpired {
            let fresh = try await refresh()
            do {
                return try await call(fresh.accessToken)
            } catch APIError.tokenExpired {
                await lose(.sessionRevoked)
                throw APIError.sessionRevoked
            } catch let e as APIError where e == .sessionRevoked || e == .accountDeleted {
                await lose(e)
                throw e
            }
        } catch let e as APIError where e == .sessionRevoked || e == .accountDeleted {
            await lose(e)
            throw e
        }
    }

    private func lose(_ e: APIError) async {
        guard session != nil else { return }
        discard()
        await onLoss?(e == .accountDeleted ? .accountDeleted : .revoked)
    }
}
