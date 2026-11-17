import SwiftUI
import ToriStore
import ToriUI
import UniformTypeIdentifiers

/// Settings → Data (doc 35 §3.10–3.11, wireframe 11-1 SD6, E3, E4): Export, Restore from backup, Tags, and the red
/// "Remove all data from this device" (Product OQ-16 closed: it also signs out).
struct DataView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    let store: ToriStore

    @State private var tagCount: Int?
    @State private var importing = false
    @State private var restoring = false
    @State private var restored: RestoreSummary?
    @State private var restoreError: StoreError?
    @State private var removal: Removal?

    /// What the remove confirmation warns about, read when the row is tapped.
    struct Removal { var signedIn: Bool; var unsynced: Int }

    var body: some View {
        List {
            Section {
                DrillRow(title: Text("Export"), value: nil) { router.push(.export) }
                DrillRow(title: Text("Restore from backup"), value: restoring ? Text("Restoring…") : nil) { importing = true }
                    .disabled(restoring)
                DrillRow(title: Text("Tags"), value: tagCount.map { Text(verbatim: "\($0)") }) { router.push(.tags) }
            }
            Section {
                Button("Remove all data from this device", role: .destructive) {
                    removal = Removal(signedIn: (env.syncCoordinator.model.status?.state ?? .localOnly) != .localOnly,
                                      unsynced: (try? store.pendingRecordCount()) ?? 0)
                }
            }
        }
        .navigationTitle(Text("Data"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let tags = store.observe { try $0.allTags().count }
            do { for try await n in tags { tagCount = n } } catch {}
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { restore(url) }
        }
        .alert(Text("Backup restored"), isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } })) {
            Button("OK") {}
        } message: {
            if let s = restored { RestoreText.summary(s) }
        }
        .alert(restoreError == .updateRequired ? Text("Update the app") : Text("This is not a ToriWords backup"),
               isPresented: Binding(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK") {}
        } message: {
            if restoreError == .updateRequired {
                Text("This backup was made by a newer version of ToriWords. Update the app to restore it. Nothing was changed.")
            } else {
                Text("Choose a .json file exported from ToriWords. Nothing was changed.")
            }
        }
        .alert(Text("Remove all data from this device?"),
               isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { _ in
            Button("Remove", role: .destructive, action: removeAll)
            Button("Cancel", role: .cancel) {}
        } message: { r in
            RestoreText.removalWarning(r)
        }
    }

    private func restore(_ url: URL) {
        restoring = true
        Task {
            defer { restoring = false }
            // §14.2: one sync cycle first, so words deleted on the account count as "deleted earlier".
            await env.sync?.syncIfSignedIn()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let summary = try await Task.detached { [store] in try store.restore(try Data(contentsOf: url)) }.value
                restored = summary
                env.didChangeData()
                await env.sync?.syncIfSignedIn()
            } catch let error as StoreError {
                restoreError = error
            } catch {
                restoreError = .notABackup
            }
        }
    }

    private func removeAll() {
        Task {
            // Signing out first stops sync; then the wipe (it also clears the auth keys of sync_state).
            try? await env.syncCoordinator.signOut()
            try? store.removeAllDataFromDevice(signOut: {})
            env.didChangeData()
        }
    }
}

enum RestoreText {
    static func summary(_ s: RestoreSummary) -> Text {
        let main = Text("Imported \(s.imported + s.merged) words, \(s.merged) merged with existing.")
        guard s.deletedEarlier > 0 else { return main }
        return Text("\(main) \(Text("\(s.deletedEarlier) words were deleted earlier and were not restored."))")
    }

    static func removalWarning(_ r: DataView.Removal) -> Text {
        if !r.signedIn {
            return Text("All your words, review history and tags are deleted from this device. This can't be undone.")
        }
        let base = Text("Your words are deleted from this device and you are signed out. They stay in your account.")
        guard r.unsynced > 0 else { return base }
        return Text("\(base) \(Text("\(r.unsynced) unsynced changes will be lost."))")
    }
}

// MARK: Export (11-1 E1, E2)

struct ExportView: View {
    @Environment(AppEnvironment.self) private var env
    let store: ToriStore

    @State private var format: ExportFormat = .backup
    @State private var wordCount: Int?
    @State private var job: Task<Void, Never>?
    @State private var file: ExportedFile?
    @State private var failed = false

    struct ExportedFile: Identifiable { let url: URL; var id: URL { url } }

    var body: some View {
        List {
            Section {
                option(.backup, title: Text("Backup (JSON)"),
                       detail: Text("Everything, including review history. Use it to restore."))
                option(.csv, title: Text("Spreadsheet (CSV)"),
                       detail: Text("One row per word. No review history; can't be restored."))
            }
            Section {
                if job != nil {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(format == .backup ? "Preparing backup…" : "Preparing spreadsheet…")
                        ProgressView()
                        Button("Cancel", role: .cancel) { job?.cancel(); job = nil }
                    }
                } else {
                    Button { export() } label: { Text("Export \(wordCount ?? 0) words") }
                        .buttonStyle(.toriPrimary)
                        .disabled((wordCount ?? 0) == 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } footer: {
                if wordCount == 0 {
                    Text("Add words to export them.")
                } else {
                    Text("Files with dictionary data include the Wiktionary attribution (CC BY-SA).")
                }
            }
        }
        .navigationTitle(Text("Export"))
        .navigationBarTitleDisplayMode(.inline)
        .task { wordCount = try? store.liveEntryCount() }
        .sheet(item: $file) { ShareSheet(items: [$0.url]) }
        .alert(Text("Something went wrong"), isPresented: $failed) { Button("OK") {} }
        .onDisappear { job?.cancel() }
    }

    private func option(_ value: ExportFormat, title: Text, detail: Text) -> some View {
        Button { format = value } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    title.foregroundStyle(Palette.text)
                    detail.font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                if format == value { Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityHidden(true) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(format == value ? .isSelected : [])
        .disabled(job != nil)
    }

    private func export() {
        let format = format
        let attribution = (env.dictionary as? any DictionaryAttribution)?.licenceText ?? ExportFile.defaultAttribution
        let name = ExportFile.name(format, at: Date())
        let offset = Now.utcOffsetMin
        job = Task {
            do {
                // ponytail: no "X of Y words" — the store builds the file in one call; indeterminate progress + Cancel.
                let url = try await Task.detached { [store] in
                    let data = try ExportFile.data(format, from: store, attribution: attribution, utcOffsetMin: offset)
                    let url = FileManager.default.temporaryDirectory.appending(path: name)
                    try data.write(to: url, options: .atomic)
                    return url
                }.value
                if !Task.isCancelled { file = ExportedFile(url: url) }
            } catch {
                if !Task.isCancelled { failed = true }
            }
            // Cancel already cleared `job` (and may have started another export).
            if !Task.isCancelled { job = nil }
        }
    }
}

/// The iOS share sheet (Save to Files, AirDrop, Mail…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
