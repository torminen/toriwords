import SwiftUI
import ToriEnrichment
import ToriUI
import Translation

/// Settings → Translation: Apple Translation status
/// with **Download**, and the bundled dictionary. When EN→RU becomes installed, words whose enrichment found nothing
/// get another try (`retryUnavailable`).
struct TranslationView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: LanguageAvailability.Status?
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        List {
            Section {
                LabeledContent {
                    if status == .supported {
                        Button("Download") { requestDownload() }
                    } else if let status {
                        status == .installed ? Text("Ready") : Text("Not available")
                    } else {
                        ProgressView()
                    }
                } label: { Text("On-device translation") }
                LabeledContent {
                    Text("Bundled")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dictionary (Wiktionary)")
                        if let version = env.dictionary?.version {
                            Text("Version \(version)").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            } header: {
                Text("Translation")
            } footer: {
                footer
            }
        }
        .navigationTitle(Text("Translation"))
        .navigationBarTitleDisplayMode(.inline)
        // The system shows its own download prompt; `prepareTranslation` returns when the user answered.
        .translationTask(download) { session in
            nonisolated(unsafe) let session = session // Not Sendable; used only here.
            try? await session.prepareTranslation()
            await refresh()
        }
        // Also re-checked when coming back from iOS Settings, where the languages can be downloaded too.
        .task(id: scenePhase == .active) { await refresh() }
    }

    @ViewBuilder
    private var footer: some View {
        switch status {
        case .supported:
            Text("""
                English → Russian translation runs on this iPhone once its language data is downloaded. Tap Download, \
                or add English and Russian in iOS Settings → Apps → Translate → Downloaded Languages. \
                The dictionary works without it.
                """)
        case .unsupported:
            Text("Apple Translation is not available on this device. The built-in dictionary still suggests translations.")
        default:
            Text("Translations for new words come from the built-in dictionary first, then from Apple Translation on this iPhone.")
        }
    }

    private func requestDownload() {
        if download == nil {
            download = .init(source: AppleTranslator.source, target: AppleTranslator.target)
        } else {
            download?.invalidate()
        }
    }

    private func refresh() async {
        let previous = status
        let current = await AppleTranslator.availability()
        status = current
        if current == .installed, let previous, previous != .installed {
            _ = try? await env.enrichment?.retryUnavailable()
        }
    }
}
