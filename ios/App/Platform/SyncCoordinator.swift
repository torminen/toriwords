import Foundation
import Network
import Observation
import ToriStore
import ToriSync

/// What the Account screen (9c) binds to. `status` is nil when sync is not configured (local-only build).
@MainActor @Observable
final class SyncStatusModel {
    fileprivate(set) var status: SyncStatus?
    var isAvailable: Bool { status != nil }
}

/// Real `SyncCoordinating`: owns the `SyncEngine` and its triggers (doc 36 §11.5, §12).
@MainActor
final class SyncCoordinator: SyncCoordinating {
    let model = SyncStatusModel()
    let google = AppConfig.google
    private(set) var engine: SyncEngine?
    private let baseURL = AppConfig.apiBaseURL
    private let sessionStore = KeychainSessionStore(service: "com.toriwords.app.session")
    private var started: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []
    private let pathMonitor = NWPathMonitor()

    func purgeLeftoverTokens() { try? sessionStore.clear() }

    /// After the store opened (launch step 3). Builds the engine only when a backend is configured.
    func attach(store: ToriStore) {
        guard engine == nil, let baseURL, let deviceID = try? store.thisDeviceID() else { return }
        let engine = SyncEngine(.init(store: store, transport: URLSessionTransport(baseURL: baseURL),
                                      sessionStore: sessionStore, appVersion: AppConfig.appVersion, deviceID: deviceID))
        self.engine = engine
        started = Task { try? await engine.start() }
        tasks.append(Task { [model] in
            for await status in await engine.statusUpdates() { model.status = status }
        })
        // ~5 s after a local change: the outbox grew (sync's own acks only shrink it).
        tasks.append(Task {
            var last = (try? store.read { try $0.pendingChangeCount() }) ?? 0
            let values = store.observe { try $0.pendingChangeCount() }
            do {
                for try await count in values {
                    if count > last { await engine.localChange() }
                    last = count
                }
            } catch {}
        })
        pathMonitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { await engine.networkPathChanged(satisfied: satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.toriwords.path"))
    }

    func syncIfSignedIn() async {
        await started?.value
        await engine?.foreground()
    }

    func didEnterBackground() async { await engine?.background() }

    func backgroundRefresh() async {
        await started?.value
        await engine?.sync(.backgroundRefresh)
    }

    // MARK: Account screen (9c)

    func signIn(_ credential: SignInCredential) async throws -> SignInResult? {
        await started?.value
        return try await engine?.signIn(credential)
    }

    func resolveAccountChoice(_ choice: AccountChoice) async -> ChoiceResult? { await engine?.resolveAccountChoice(choice) }
    func signOut() async throws { try await engine?.signOut() }
    func deleteAccount(removeLocalData: Bool) async throws { try await engine?.deleteAccount(removeLocalData: removeLocalData) }
    func syncNow() async { await engine?.sync(.manual) }
    func dismissNotice() async { await engine?.dismissNotice() }
}
