import Foundation
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
