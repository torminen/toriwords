import SwiftUI
import ToriStore
import ToriSync
import ToriUI
import UIKit

/// Settings → iCloud sync: status, Sync now, Back up this device again (after a deletion), Delete iCloud data.
/// There is no in-app switch: the iOS per-app iCloud toggle turns sync off.
struct CloudSyncView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    let store: ToriStore

    @State private var confirmDelete = false
    @State private var busy = false
    @State private var failure: Failure?

    enum Failure { case offline, deleteFailed, backUpFailed }

    private var sync: SyncCoordinator { env.syncCoordinator }

    var body: some View {
        let status = sync.model.status
        List {
            Section {
                LabeledContent { status.map(CloudSyncText.status) ?? Text(verbatim: "—") } label: { Text("Status") }
                Button("Sync now") { Task { await sync.syncNow() } }
                    .disabled(!(status?.syncNowEnabled ?? false))
                if status?.state == .cloudDeleted {
                    Button("Back up this device again") { run(.backUpFailed) { try await sync.backUpAgain() } }
                }
            }
            Section {
                Button("Delete iCloud data…", role: .destructive) { confirmDelete = true }
                    .disabled(status?.state == .cloudDeleted || status?.state == .iCloudOff)
            }
            Section {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text("Your words sync through your private iCloud between devices signed in to the same Apple Account. To stop syncing on this device, turn off iCloud for ToriWords in iOS Settings; your words stay on this device.")
            }
        }
        .navigationTitle(Text("iCloud sync"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .confirmationDialog(Text("This deletes your words from iCloud. Your other devices keep their copies but stop syncing."),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete iCloud data", role: .destructive) { run(.deleteFailed) { try await sync.deleteCloudData() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert(failure == .offline ? Text("No internet connection") : Text("Something went wrong"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: {
            switch failure {
            case .offline: Text("Connect to the internet and try again. Nothing was changed.")
            case .deleteFailed: Text("iCloud data was not deleted. Try again later.")
            case .backUpFailed, nil: Text("Try again later.")
            }
        }
    }

    private func run(_ onError: Failure, _ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await body() } catch CloudError.network { failure = .offline } catch { failure = onError }
        }
    }
}

enum CloudSyncText {
    /// Settings root value of the iCloud sync row.
    static func rowValue(_ status: SyncStatus) -> Text {
        switch status.state {
        case .idle, .synced: Text("On")
        case .syncing: Text("Syncing…")
        case .waitingForNetwork: Text("Waiting for network")
        case .iCloudOff: Text("Off")
        case .quotaFull: Text("Storage full")
        case .cloudDeleted: Text("Deleted")
        }
    }

    /// iCloud sync → Status.
    static func status(_ status: SyncStatus) -> Text {
        switch status.state {
        case .iCloudOff: return Text("iCloud is off: words stay on this device")
        case .quotaFull: return Text("iCloud storage is full")
        case .cloudDeleted: return Text("iCloud data was deleted")
        case .waitingForNetwork: return Text("Waiting for network")
        case .idle, .syncing, .synced: break
        }
        if status.clockWarning { return Text("Check your device time") }
        switch status.state {
        case .synced(let at):
            let date = Date(timeIntervalSince1970: Double(at) / 1000)
            return Text("Synced \(date.formatted(.relative(presentation: .named)))")
        case .syncing: return Text("Syncing…")
        default: return Text("Not synced yet")
        }
    }
}
