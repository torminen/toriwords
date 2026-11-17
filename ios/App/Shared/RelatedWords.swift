import SwiftUI
import ToriCore
import ToriEnrichment
import ToriStore
import ToriUI

/// Related words (P1, doc 35 §3.7, 10-3 RW1/RW2): up to 8 rows with + Add and ✕; saved ones show "✓ In vocabulary".
/// Hidden when the dictionary knows none. ✕ hides a row for this screen only (not stored).
struct RelatedWords: View {
    let word: String
    var title: Text?
    @Environment(AppEnvironment.self) private var env
    @State private var items: [Completion] = []
    @State private var saved: Set<String> = []
    @State private var dismissed: Set<String> = []
    @State private var preview: Completion?

    static let limit = 8

    var body: some View {
        let visible = items.filter { !dismissed.contains($0.text) }
        Group {
            if !visible.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    (title ?? Text("Related words")).font(Typography.heading).accessibilityAddTraits(.isHeader)
                    if visible.allSatisfy({ saved.contains(TextKey.matchKey($0.text)) }) {
                        Text("You have all related words").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(visible, id: \.text) { row($0) }
                }
            }
        }
        .task(id: word) { load() }
        .sheet(item: $preview) { item in
            RelatedPreview(item: item, isSaved: saved.contains(TextKey.matchKey(item.text))) { add(item) }
        }
    }

    private func row(_ item: Completion) -> some View {
        let isSaved = saved.contains(TextKey.matchKey(item.text))
        return HStack(spacing: Spacing.m) {
            Button { preview = item } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.text).font(Typography.body.weight(.semibold)).foregroundStyle(Palette.text)
                    if let t = item.translation {
                        Text(verbatim: t).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isSaved {
                Badge("✓ In vocabulary", fill: Palette.successFill)
            } else {
                Button("Add") { add(item) }.font(Typography.body.weight(.semibold))
                Button { dismissed.insert(item.text) } label: { Image(systemName: "xmark") }
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityLabel(Text("Hide \(item.text)"))
            }
        }
        .frame(minHeight: 44)
    }

    private func load() {
        items = env.dictionarySearch.related(to: word, limit: Self.limit)
        refreshSaved()
    }

    private func refreshSaved() {
        guard let store = env.store else { return }
        saved = Set(items.compactMap { item in
            (try? store.read { try $0.entryID(matching: item.text) }).flatMap { $0 }.map { _ in TextKey.matchKey(item.text) }
        })
    }

    /// One-tap add with the primary translation and no sentence; source "Suggested from '<word>'" (proposal, AQ-19).
    private func add(_ item: Completion) {
        guard let store = env.store else { return }
        let senses = item.translation.map { [NewSense(translation: $0, definition: item.definition, partOfSpeech: item.partOfSpeech, source: .wiktionary)] } ?? []
        _ = try? store.capture(CaptureInput(term: item.text, capturedAt: Now.ms, origin: "typed", senses: senses,
                                            source: SourceInput(kind: .suggested, title: word)))
        env.didChangeWords()
        refreshSaved()
        if let enrichment = env.enrichment { Task { _ = try? await enrichment.runPending() } }
    }
}

extension Completion: @retroactive Identifiable {
    public var id: String { text }
}

/// Tapping a related word: word with ▶, part of speech, translation, Add to my words, Close (proposal).
private struct RelatedPreview: View {
    let item: Completion
    let isSaved: Bool
    let add: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: item.text).font(Typography.cardWord)
                SpeakButton(item.text)
            }
            if let pos = item.partOfSpeech {
                Text(verbatim: pos).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            }
            if let t = item.translation { Text(verbatim: t).font(Typography.heading) }
            if let d = item.definition { Text(verbatim: d).font(Typography.body).foregroundStyle(Palette.textSecondary) }
            Spacer(minLength: Spacing.l)
            if isSaved {
                Badge("✓ In vocabulary", fill: Palette.successFill)
            } else {
                Button("Add to my words") { add(); dismiss() }.buttonStyle(.toriPrimary)
            }
            Button("Close") { dismiss() }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(Spacing.xl)
        .presentationDetents([.medium])
    }
}
