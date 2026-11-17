import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Settings → Data → Tags (P1, doc 35 §3.6; 10-3 T3, T4): tags A–Z with word counts; tap to rename, swipe to delete;
/// renaming to an existing name offers a merge.
struct TagsView: View {
    let store: ToriStore
    @Environment(AppEnvironment.self) private var env
    @State private var tags: [TagRow] = []
    @State private var counts: [ToriID: Int] = [:]
    @State private var renaming: TagRow?
    @State private var newName = ""
    @State private var mergeInto: String?
    @State private var deleting: TagRow?

    var body: some View {
        List {
            ForEach(tags, id: \.id) { tag in
                Button { renaming = tag; newName = tag.name } label: {
                    LabeledContent {
                        Text("\(counts[tag.id] ?? 0) words")
                    } label: {
                        Text(verbatim: tag.name).foregroundStyle(Palette.text)
                    }
                    .contentShape(Rectangle())
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { deleting = tag } label: { Text("Delete") }
                }
                .accessibilityHint(Text("Renames the tag."))
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if tags.isEmpty {
                EmptyStateView(title: Text("No tags yet"), message: Text("Add tags to words in Add or when editing a word."))
            }
        }
        .navigationTitle(Text("Tags"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await observe() }
        .alert(Text("Rename tag"), isPresented: Binding(get: { renaming != nil && mergeInto == nil },
                                                        set: { if !$0 && mergeInto == nil { renaming = nil } })) {
            TextField(text: $newName) { Text("Name") }
            Button("Save") { rename(merge: false) }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert(Text("“\(mergeInto ?? "")” already exists"), isPresented: Binding(
            get: { mergeInto != nil }, set: { if !$0 { mergeInto = nil; renaming = nil } })) {
            Button("Merge") { rename(merge: true) }
            Button("Cancel", role: .cancel) { mergeInto = nil; renaming = nil }
        } message: {
            Text("Merge “\(renaming?.name ?? "")” into “\(mergeInto ?? "")”?")
        }
        .alert(Text("Delete tag “\(deleting?.name ?? "")”?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed from \(deleting.flatMap { counts[$0.id] } ?? 0) words. The words stay.")
        }
    }

    private func observe() async {
        let observation = store.observe { r in TagsSnapshot(tags: try r.allTags(), counts: try r.tagCounts()) }
        do {
            for try await s in observation {
                tags = s.tags
                counts = s.counts
            }
        } catch {}
    }

    private func rename(merge: Bool) {
        guard let tag = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !TextKey.tagKey(name).isEmpty else { renaming = nil; return }
        switch try? store.renameTag(tag.id, to: name, mergeIfDuplicate: merge) {
        case .duplicate(let other):
            mergeInto = tags.first { $0.id == other }?.name ?? name
        default:
            mergeInto = nil
            renaming = nil
            env.didChangeWords()
        }
    }

    private func delete() {
        guard let tag = deleting else { return }
        try? store.deleteTag(tag.id)
        deleting = nil
    }
}

private struct TagsSnapshot: Equatable, Sendable {
    var tags: [TagRow]
    var counts: [ToriID: Int]
}
