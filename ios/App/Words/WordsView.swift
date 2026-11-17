import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Words list (doc 35 §3.5, Product §5.7; wireframes 3-5 W1–W3, 8-6 A3, 10-3 T2).
struct WordsView: View {
    let store: ToriStore
    @State private var query: WordsQuery
    @State private var rows: [WordRow] = []
    @State private var tags: [TagRow] = []
    @State private var tagCounts: [ToriID: Int] = [:]
    @State private var showTagFilter = false
    @State private var confirmDelete: WordRow?
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(PendingDeletion.self) private var deletion

    init(store: ToriStore, query: WordsQuery) {
        self.store = store
        _query = State(initialValue: query)
    }

    private var visible: [WordRow] { rows.filter { !deletion.hidden.contains($0.id) } }

    var body: some View {
        List {
            Section {
                ForEach(visible, id: \.id) { row in
                    Button { router.push(.entry(row.id)) } label: { WordRowView(row: row) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeActions(row) }
                }
            } header: {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    chips.padding(.horizontal, -Spacing.l)
                    Text(countLine).font(Typography.secondary).foregroundStyle(Palette.textSecondary).textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .overlay { noResults }
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search words, translations, sentences"))
        .navigationTitle(Text("Words"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $query.sort) {
                        Text("Newest").tag(WordsQuery.Sort.newest)
                        Text("A–Z").tag(WordsQuery.Sort.alphabetical)
                        Text("Next due").tag(WordsQuery.Sort.nextDue)
                    } label: { Text("Sort") }
                } label: {
                    Label { Text("Sort") } icon: { Image(systemName: "arrow.up.arrow.down") }
                }
                Button { router.push(.add(text: nil)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Add a word"))
            }
        }
        .task(id: query) { await observe() }
        .sheet(isPresented: $showTagFilter) {
            TagFilterSheet(tags: tags, counts: tagCounts, selected: $query.tags, store: store, query: query)
        }
        .alert(Text("Delete “\(confirmDelete?.text ?? "")”?"), isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let row = confirmDelete { deletion.schedule([row.id], word: row.text) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed with its review history on all your devices.")
        }
    }

    /// Live list: re-read on every change of `user.sqlite` (edits, sync, enrichment).
    private func observe() async {
        let q = query
        let observation = store.observe { r in
            WordsSnapshot(rows: try r.words(q), tags: try r.allTags(), counts: try r.tagCounts())
        }
        do {
            for try await s in observation {
                rows = s.rows
                tags = s.tags
                tagCounts = s.counts
            }
        } catch {}
    }

    @ViewBuilder
    private func swipeActions(_ row: WordRow) -> some View {
        Button(role: .destructive) { confirmDelete = row } label: { Text("Delete") }
        if row.stage == .known || row.stage == .paused {
            Button { setStatus(row, .active) } label: { Text("Resume learning") }.tint(Palette.accent)
        } else {
            Button { setStatus(row, .paused) } label: { Text("Pause") }.tint(.gray)
            Button { setStatus(row, .known) } label: { Text("I already know this") }.tint(Palette.success)
        }
    }

    private func setStatus(_ row: WordRow, _ status: EntryStatus) {
        try? store.setStatus([row.id], status)
        env.didChangeWords()
    }

    // MARK: Chips and count

    private enum ChipID: Hashable { case filter(WordsQuery.Filter), tag }

    private var chips: some View {
        let filters: [(WordsQuery.Filter, LocalizedStringResource)] = [
            (.all, "All"), (.needsTranslation, Strings.stageNeedsTranslation), (.checkTranslation, Strings.checkTranslationTitle),
            (.phrases, "Phrases"), (.stage(.new), Strings.stageNew), (.stage(.learning), Strings.stageLearning),
            (.stage(.knownWell), Strings.stageKnownWell), (.stage(.known), Strings.stageKnown), (.stage(.paused), Strings.stagePaused),
        ]
        var items = filters.map { ChipsRow<ChipID>.Item(id: .filter($0.0), label: Text($0.1)) }
        items.append(.init(id: .tag, label: tagChipLabel))
        var selected: Set<ChipID> = [.filter(query.filter)]
        if !query.tags.isEmpty { selected.insert(.tag) }
        return ChipsRow(items, selected: selected) { id in
            switch id {
            case .filter(let f): query.filter = f
            case .tag: showTagFilter = true
            }
        }
    }

    /// "Tag", "work", "work +1".
    private var tagChipLabel: Text {
        let names = tags.filter { query.tags.contains($0.id) }.map(\.name)
        guard let first = names.first else { return Text("Tag") }
        return names.count == 1 ? Text(verbatim: first) : Text("\(first) +\(names.count - 1)")
    }

    private var countLine: LocalizedStringResource {
        let n = visible.count
        return switch query.sort {
        case .newest: "\(n) words · newest first"
        case .alphabetical: "\(n) words · A–Z"
        case .nextDue: "\(n) words · next due first"
        }
    }

    @ViewBuilder
    private var noResults: some View {
        let search = query.search.trimmingCharacters(in: .whitespaces)
        if visible.isEmpty, !search.isEmpty {
            EmptyStateView(title: Text("No words match “\(search)”"), actionTitle: Text("Add “\(search)”")) {
                router.push(.add(text: search))
            }
        }
    }
}

private struct WordsSnapshot: Equatable, Sendable {
    var rows: [WordRow]
    var tags: [TagRow]
    var counts: [ToriID: Int]
}

/// Word (semibold), the translation line, and the stage marker (W1, U14).
struct WordRowView: View {
    let row: WordRow

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.text).font(Typography.body.weight(.semibold)).foregroundStyle(Palette.text)
                TranslationLine.text(row.translation).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.s)
            StageMarker(StageMarker.Kind(row.stage))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension StageMarker.Kind {
    init(_ stage: WordStage) {
        self = switch stage {
        case .needsTranslation: .needsTranslation
        case .new: .new
        case .learning: .learning
        case .knownWell: .knownWell
        case .known: .known
        case .paused: .paused
        }
    }
}

/// "Filter by tag" (10-3 T2): checkable tags with counts, Clear · Done, Show N words. Several tags match any-of.
private struct TagFilterSheet: View {
    let tags: [TagRow]
    let counts: [ToriID: Int]
    @Binding var selected: Set<ToriID>
    let store: ToriStore
    let query: WordsQuery
    @State private var draft: Set<ToriID> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if tags.isEmpty {
                    Text("No tags yet. Add tags to words in Add or when editing a word.").foregroundStyle(Palette.textSecondary)
                }
                ForEach(tags, id: \.id) { tag in
                    Button {
                        if draft.contains(tag.id) { draft.remove(tag.id) } else { draft.insert(tag.id) }
                    } label: {
                        HStack {
                            Image(systemName: draft.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.contains(tag.id) ? Palette.accent : Palette.border)
                            Text(verbatim: tag.name).foregroundStyle(Palette.text)
                            Spacer()
                            Text(verbatim: "\(counts[tag.id] ?? 0)").foregroundStyle(Palette.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.contains(tag.id) ? [.isSelected] : [])
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { apply() } label: { Text("Show \(matching) words") }
                    .buttonStyle(.toriPrimary)
                    .padding(Spacing.l)
            }
            .navigationTitle(Text("Filter by tag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Clear") { draft = [] } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { apply() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { draft = selected }
    }

    private var matching: Int {
        var q = query
        q.tags = draft
        return (try? store.read { try $0.words(q) }.count) ?? 0
    }

    private func apply() {
        selected = draft
        dismiss()
    }
}
