import CloudKit
import Foundation
import Network
import Observation
import ToriStore
import ToriSync

/// What Settings → iCloud sync binds to. `status` is nil until the store is open.
@MainActor @Observable
final class SyncStatusModel {
    fileprivate(set) var status: SyncStatus?
}

/// Real `SyncCoordinating`: owns the `SyncEngine` over the iCloud private database and its triggers.
@MainActor
final class SyncCoordinator: SyncCoordinating {
    static let container = "iCloud.com.toriwords.app"

    let model = SyncStatusModel()
    private(set) var engine: SyncEngine?
    private var started: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []
    private let pathMonitor = NWPathMonitor()
    private var accountObserver: NSObjectProtocol?

    /// After the store opened (launch step 3).
    func attach(store: ToriStore) {
        guard engine == nil else { return }
        let engine = SyncEngine(.init(store: store, cloud: CloudKitDatabase(container: Self.container),
                                      appVersion: AppConfig.appVersion))
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
        // iCloud signed in/out or switched: the cycle's account check handles it.
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { _ in
            Task { await engine.sync(.foreground) }
        }
    }

    func syncIfActive() async {
        await started?.value
        await engine?.foreground()
    }

    func didEnterBackground() async { await engine?.background() }

    func backgroundRefresh() async {
        await started?.value
        await engine?.sync(.backgroundRefresh)
    }

    // MARK: iCloud sync screen

    func syncNow() async { await engine?.sync(.manual) }
    func deleteCloudData() async throws { try await engine?.deleteCloudData() }
    func backUpAgain() async throws { try await engine?.backUpAgain() }
}
