import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Words list.
/// Select mode (UQ-9: "Select" in the ••• menu or long-press a row): checkboxes, Cancel · N selected · Select all,
/// bottom bar Tag · Known · Pause · Delete (Resume learning when every selected word is Known or Paused).
struct WordsView: View {
    let store: ToriStore
    @State private var query: WordsQuery
    @State private var rows: [WordRow] = []
    @State private var tags: [TagRow] = []
    @State private var tagCounts: [ToriID: Int] = [:]
    @State private var showTagFilter = false
    @State private var confirmDelete: WordRow?
    @State private var selecting = false
    @State private var selection: Set<ToriID> = []
    @State private var bulkTagging = false
    @State private var confirmBulkDelete = false
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(PendingDeletion.self) private var deletion

    init(store: ToriStore, query: WordsQuery) {
        self.store = store
        _query = State(initialValue: query)
    }

    private var visible: [WordRow] { rows.filter { !deletion.hidden.contains($0.id) } }
    /// Selected rows still in the list (a filter, search, sync or delete can drop some), in list order.
    private var selectedRows: [WordRow] { visible.filter { selection.contains($0.id) } }

    var body: some View {
        List {
            Section {
                ForEach(visible, id: \.id) { row in
                    if selecting {
                        selectableRow(row)
                    } else {
                        Button { router.push(.entry(row.id)) } label: { WordRowView(row: row) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeActions(row) }
                            .contextMenu {
                                Button { startSelecting(row.id) } label: {
                                    Label { Text("Select") } icon: { Image(systemName: "checkmark.circle") }
                                }
                            }
                    }
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
        .navigationBarBackButtonHidden(selecting)
        .toolbar { if selecting { selectToolbar } else { browseToolbar } }
        .sheet(isPresented: $bulkTagging) {
            BulkTagSheet(count: selectedRows.count, available: tags, counts: tagCounts, onAdd: addTags)
        }
        .alert(Text("Delete \(selectedRows.count) words?"), isPresented: $confirmBulkDelete) {
            Button("Delete \(selectedRows.count) words", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They are removed with their review history on all your devices.")
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

    // MARK: Toolbars

    @ToolbarContentBuilder
    private var browseToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button { startSelecting(nil) } label: {
                    Label { Text("Select") } icon: { Image(systemName: "checkmark.circle") }
                }
                .disabled(visible.isEmpty)
                Picker(selection: $query.sort) {
                    Text("Newest").tag(WordsQuery.Sort.newest)
                    Text("A–Z").tag(WordsQuery.Sort.alphabetical)
                    Text("Next due").tag(WordsQuery.Sort.nextDue)
                } label: {
                    Label { Text("Sort") } icon: { Image(systemName: "arrow.up.arrow.down") }
                }
                .pickerStyle(.menu)
            } label: {
                Label { Text("More") } icon: { Image(systemName: "ellipsis.circle") }
            }
            Button { router.push(.add(text: nil)) } label: { Image(systemName: "plus") }
                .accessibilityLabel(Text("Add a word"))
        }
    }

    @ToolbarContentBuilder
    private var selectToolbar: some ToolbarContent {
        let count = selectedRows.count
        let allSelected = !visible.isEmpty && count == visible.count
        ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: stopSelecting) }
        ToolbarItem(placement: .principal) { Text("\(count) selected").font(.headline) }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                selection = allSelected ? [] : Set(visible.map(\.id))
            } label: {
                allSelected ? Text("Deselect all") : Text("Select all")
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            let resumable = count > 0 && selectedRows.allSatisfy { $0.stage == .known || $0.stage == .paused }
            Button("Tag") { bulkTagging = true }
            Spacer()
            if resumable {
                Button("Resume learning") { setSelectedStatus(.active) }
            } else {
                Button("Known") { setSelectedStatus(.known) }
                    .accessibilityLabel(Text("I already know this"))
                Spacer()
                Button("Pause") { setSelectedStatus(.paused) }
            }
            Spacer()
            Button("Delete", role: .destructive) { confirmBulkDelete = true }
                .tint(Palette.danger)
        }
    }

    // MARK: Select mode

    private func selectableRow(_ row: WordRow) -> some View {
        let isSelected = selection.contains(row.id)
        return Button {
            if isSelected { selection.remove(row.id) } else { selection.insert(row.id) }
        } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.border)
                    .accessibilityHidden(true)
                WordRowView(row: row)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func startSelecting(_ first: ToriID?) {
        selection = first.map { [$0] } ?? []
        withAnimation { selecting = true }
    }

    private func stopSelecting() {
        withAnimation { selecting = false }
        selection = []
    }

    /// Bulk actions are one store transaction each; the mode ends after every action.
    private func setSelectedStatus(_ status: EntryStatus) {
        try? store.setStatus(selectedRows.map(\.id), status)
        env.didChangeWords()
        stopSelecting()
    }

    private func addTags(_ names: [String]) {
        try? store.tag(selectedRows.map(\.id), names: names)
        env.didChangeWords()
        stopSelecting()
    }

    /// One Undo window for the whole batch (B2), like a single delete.
    private func deleteSelected() {
        let ids = selectedRows.map(\.id)
        guard !ids.isEmpty else { return }
        deletion.schedule(ids, message: "\(ids.count) words deleted")
        stopSelecting()
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

/// Bulk Tag (B1 → the T1 picker): only adds the chosen tags (UQ-10).
private struct BulkTagSheet: View {
    let count: Int
    let available: [TagRow]
    let counts: [ToriID: Int]
    let onAdd: ([String]) -> Void
    @State private var names: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TagEditor(tags: $names, available: available, counts: counts)
                } footer: {
                    Text("Adds tags to \(count) words. Tags they already have stay.")
                }
            }
            .navigationTitle(Text("Add tags"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onAdd(names)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(names.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
