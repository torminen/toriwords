import SwiftUI
import ToriStore
import ToriSync
import ToriUI

/// Settings → Account (doc 35 §3.10, wireframes 4-6 S2–S5b; Product §5.8; doc 36 §11.10, §12.5–12.7).
/// Prompts and summaries are alerts; the engine's one-time `notices` are shown here in order.
struct AccountView: View {
    @Environment(AppEnvironment.self) private var env
    let store: ToriStore

    @State private var lastProvider: SignInProvider?
    @State private var busy = false
    @State private var failure: LocalizedStringResource?
    @State private var signOutNote: Int?
    @State private var confirmDelete = false
    /// Tapping the paused Status row reopens the "Words from another account" prompt.
    @State private var reopenedPrompt: Int?

    private var sync: any SyncCoordinating { env.syncOrLocal }

    var body: some View {
        let status = sync.status
        List {
            if status.state == .localOnly { signedOut } else { signedIn(status) }
        }
        .navigationTitle(Text("Account"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .task(id: status.state) {
            lastProvider = (try? store.syncState(.lastProvider)).flatMap { $0 }.flatMap(SignInProvider.init(rawValue:))
        }
        .alert(Text("Something went wrong"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: {
            if let failure { Text(failure) }
        }
        .alert(Text("Sign out?"), isPresented: Binding(get: { signOutNote != nil }, set: { if !$0 { signOutNote = nil } })) {
            Button("Sign out", role: .destructive) { run { try await sync.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let n = signOutNote, n > 0 {
                Text("Your words stay on this device. \(n) unsynced changes will be uploaded next time you sign in.")
            } else {
                Text("Your words stay on this device.")
            }
        }
        .confirmationDialog(Text("This deletes your cloud backup and signs out all devices."), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete account, keep my words on this device", role: .destructive) { deleteAccount(removeLocal: false) }
            Button("Delete account and remove my words from this device", role: .destructive) { deleteAccount(removeLocal: true) }
            Button("Cancel", role: .cancel) {}
        }
        .modifier(NoticeAlerts(sync: sync, reopenedPrompt: $reopenedPrompt, resolve: resolve))
    }

    // MARK: Signed out (S2)

    @ViewBuilder
    private var signedOut: some View {
        Section {
            Text("Your words are stored on this device. Sign in to back them up and sync between your devices. Optional.")
                .font(Typography.body)
            Button { signIn(.apple) } label: {
                Label { Text("Sign in with Apple") } icon: { Image(systemName: "apple.logo") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.toriPrimary(tint: .black))
            .listRowSeparator(.hidden)
            Button { signIn(.google) } label: { Text("Sign in with Google").frame(maxWidth: .infinity) }
                .buttonStyle(.toriSecondary)
                .listRowSeparator(.hidden)
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Apple and Google sign-ins are separate accounts. Use the same one on all your devices.")
                if let lastProvider { Text("Last time this device used: \(Text(ProviderName.of(lastProvider)))") }
            }
        }
    }

    // MARK: Signed in (S3, S3b, S4)

    @ViewBuilder
    private func signedIn(_ status: SyncStatus) -> some View {
        Section {
            LabeledContent { Text(lastProvider.map(ProviderName.of) ?? "—") } label: { Text("Signed in with") }
            if case .paused(let n) = status.state {
                Button { reopenedPrompt = n } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Status").foregroundStyle(Palette.text)
                        Text("Sync paused: choose what to do with \(n) words ›").foregroundStyle(Palette.accent)
                        Text("Removing them also deletes words added since sign-in.")
                            .font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                    }
                }
            } else {
                LabeledContent { AccountStatusText.status(status) } label: { Text("Status") }
            }
            Button("Sync now") { Task { await sync.syncNow() } }
                .disabled(!status.syncNowEnabled)
        }
        Section {
            Button("Sign out") { signOutNote = (try? store.pendingRecordCount()) ?? 0 }
        }
        Section {
            Button("Delete account", role: .destructive) { confirmDelete = true }
        } footer: {
            Text("Deleting your account needs an internet connection.")
        }
    }

    // MARK: Actions

    private func signIn(_ provider: SignInProvider) {
        busy = true
        Task {
            defer { busy = false }
            do { try await sync.signIn(with: provider) }
            catch is CancellationError {}
            catch { failure = "Couldn't sign in. Try again." }
        }
    }

    private func deleteAccount(removeLocal: Bool) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await sync.deleteAccount(removeLocalData: removeLocal)
                if removeLocal { env.didChangeData() }
            } catch APIError.offline, APIError.unreachable {
                failure = "Connect to the internet to delete your account. Nothing was changed."
            } catch {
                failure = "Your account was not deleted. Try again later."
            }
        }
    }

    private func run(_ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await body() } catch { failure = "Try again later." }
        }
    }

    private func resolve(_ choice: AccountChoice) {
        Task {
            if await sync.resolveAccountChoice(choice) == .done, choice == .remove { env.didChangeData() }
        }
    }
}

enum ProviderName {
    static func of(_ provider: SignInProvider) -> LocalizedStringResource {
        provider == .apple ? "Apple" : "Google"
    }
}

/// The engine's one-time notices (`SyncStatus.notices`, first one shown) as alerts, plus the reopened account prompt.
private struct NoticeAlerts: ViewModifier {
    let sync: any SyncCoordinating
    @Binding var reopenedPrompt: Int?
    let resolve: (AccountChoice) -> Void

    private var notice: SyncNotice? {
        if let n = reopenedPrompt { return .accountPrompt(words: n) }
        return sync.status.notices.first
    }

    private func close() {
        if reopenedPrompt != nil { reopenedPrompt = nil } else { sync.dismissNotice() }
    }

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { notice != nil }, set: { if !$0 { close() } })) {
            switch notice {
            case .accountPrompt(let n):
                Button("Add these \(n) words to this account") { close(); resolve(.add) }
                Button("Remove all \(n) words from this device", role: .destructive) { close(); resolve(.remove) }
                Button("Cancel", role: .cancel) { close() }
            case .removeNeedsNetwork:
                // OK reopens the prompt (Product §5.8).
                Button("OK") {
                    close()
                    if case .paused(let n) = sync.status.state { reopenedPrompt = n }
                }
            default:
                Button("OK") { close() }
            }
        } message: {
            message
        }
    }

    private var title: Text {
        switch notice {
        case .accountPrompt: Text("Words from another account")
        case .removeNeedsNetwork: Text("No internet connection")
        case .signedOut: Text("Signed out")
        case .accountDeletedElsewhere: Text("Account deleted")
        case .mergeSummary: Text("Vocabulary merged")
        case .backedUp, nil: Text("Backed up")
        }
    }

    @ViewBuilder
    private var message: some View {
        switch notice {
        case .accountPrompt(let n):
            Text("This device has \(n) words: ones from your previous account and any you added since signing in. Removing them deletes all \(n) from this device.")
        case .removeNeedsNetwork:
            Text("Connect to the internet to remove these words. Nothing was changed.")
        case .signedOut:
            Text("You were signed out. Sign in again to continue syncing.")
        case .accountDeletedElsewhere:
            Text("Your ToriWords account was deleted on another device. Your words stay on this device only.")
        case .mergeSummary(let device, let account, let both):
            Text("\(device) words from this device, \(account) from your account, \(both) in both.")
        case .backedUp:
            Text("Your vocabulary is backed up.")
        case nil:
            EmptyView()
        }
    }
}
