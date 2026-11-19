import SwiftUI
import ToriSync

enum AccountStatusText {
    /// Settings root value of the Account row; nil status = sync not configured (local-only build).
    static func rowValue(_ status: SyncStatus?) -> LocalizedStringResource {
        switch status?.state {
        case nil, .localOnly: "Not signed in"
        case .paused: "Sync paused"
        default: "Signed in"
        }
    }

    /// Account → Status.
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

/// `sync_state.lastProvider` values.
enum ProviderName {
    static func of(_ provider: String?) -> LocalizedStringResource? {
        switch provider {
        case "apple": "Apple"
        case "google": "Google"
        default: nil
        }
    }
}
