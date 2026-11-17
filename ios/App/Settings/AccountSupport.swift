import SwiftUI
import Observation
import ToriSync

/// Default `SyncCoordinating` until the real engine is wired: always local-only; sign-in is unavailable.
@MainActor @Observable
final class LocalOnlySync: SyncCoordinating {
    struct Unavailable: Error {}
    static let shared = LocalOnlySync()

    var status = SyncStatus(state: .localOnly, clockWarning: false, lastSyncAt: nil, notices: [])
    func purgeLeftoverTokens() {}
    func syncIfSignedIn() async {}
    func signIn(with provider: SignInProvider) async throws { throw Unavailable() }
    func syncNow() async {}
    func resolveAccountChoice(_ choice: AccountChoice) async -> ChoiceResult { .noPendingChoice }
    func signOut() async throws {}
    func deleteAccount(removeLocalData: Bool) async throws { throw Unavailable() }
    func dismissNotice() {}
}

extension AppEnvironment {
    var syncOrLocal: any SyncCoordinating { sync ?? LocalOnlySync.shared }
}

enum AccountStatusText {
    /// Settings root value of the Account row.
    static func rowValue(_ status: SyncStatus) -> LocalizedStringResource {
        switch status.state {
        case .localOnly: "Not signed in"
        case .paused: "Sync paused"
        default: "Signed in"
        }
    }
}

extension AccountStatusText {
    /// Account → Status (doc 36 §11.10).
    static func status(_ status: SyncStatus) -> Text {
        if status.clockWarning { return Text("Check your device time") }
        switch status.state {
        case .localOnly: return Text("Not signed in")
        case .firstSync, .syncing: return Text("Syncing…")
        case .synced:
            guard let at = status.lastSyncAt else { return Text("Synced") }
            let date = Date(timeIntervalSince1970: Double(at) / 1000)
            return Text("Synced \(date.formatted(.relative(presentation: .named)))")
        case .waitingForNetwork: return Text("Waiting for network")
        case .unreachable: return Text("Can't reach the server")
        case .clockSkew: return Text("Check your device time")
        case .updateRequired: return Text("Update the app to sync")
        case .paused(let n): return Text("Sync paused: choose what to do with \(n) words")
        }
    }
}
