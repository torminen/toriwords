import SwiftUI
import ToriDictionary
import ToriStore
import ToriUI

extension BundledDictionary: DictionaryAttribution {}

enum AppLinks {
    static let source = URL(string: "https://github.com/torminen/toriwords")!
    static let ccBySA = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
    static let wiktionary = URL(string: "https://en.wiktionary.org/")!
    static let kaikki = URL(string: "https://kaikki.org/")!
}

/// Settings → About.
struct AboutView: View {
    @Environment(AppEnvironment.self) private var env

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent { Text(verbatim: version) } label: { Text("Version") }
                Link(destination: AppLinks.source) {
                    LabeledContent { Text(verbatim: "GitHub ›") } label: { Text("Source code").foregroundStyle(Palette.text) }
                }
                NavigationLink { LicencesView() } label: { Text("Licences") }
            }
            Section {
                Link(destination: AppLinks.ccBySA) { Text("Dictionary data from Wiktionary, CC BY-SA") }
            } header: {
                Text("Attribution")
            }
            Section {
                Text("""
                    Your words are stored on this device and, if iCloud is on, in your private iCloud. Nobody else, including us, can read them. \
                    No analytics, tracking or crash-reporting SDKs; no usage data is collected. \
                    Only the crash and performance reports of iOS itself exist, if you allowed them in iOS Settings.
                    """)
                    .font(Typography.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle(Text("About"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Licences of bundled data and open-source libraries. Licence texts stay in English (legal text).
private struct LicencesView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                Text(verbatim: (env.dictionary as? any DictionaryAttribution)?.licenceText ?? ExportFile.defaultAttribution)
                    .font(Typography.secondary)
                Link(destination: AppLinks.wiktionary) { Text(verbatim: "Wiktionary") }
                Link(destination: AppLinks.kaikki) { Text(verbatim: "kaikki.org (wiktextract)") }
                Link(destination: AppLinks.ccBySA) { Text(verbatim: "CC BY-SA 4.0") }
            } header: {
                Text("Dictionary data")
            }
            Section {
                LabeledContent { Text(verbatim: "MIT") } label: { Text(verbatim: "GRDB.swift — Gwendal Roué") }
            } header: {
                Text("Libraries")
            }
            Section {
                LabeledContent { Text(verbatim: "Apache 2.0") } label: { Text(verbatim: "ToriWords") }
            } footer: {
                Text("The ToriWords name, logo and app icon are not covered by this licence.")
            }
        }
        .navigationTitle(Text("Licences"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
