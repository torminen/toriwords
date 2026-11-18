import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Tag picker used by Add and entry edit mode (10-3 T1): chips with ✕, an "Add tag" field, matching tags with their
/// counts and "+ Create tag “…”". Names are compared by tag key ("Work" = "work ").
struct TagEditor: View {
    @Binding var tags: [String]
    let available: [TagRow]
    let counts: [ToriID: Int]
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(tags, id: \.self) { name in
                            Button { tags.removeAll { TextKey.tagKey($0) == TextKey.tagKey(name) } } label: {
                                HStack(spacing: Spacing.xs) {
                                    Text(verbatim: name)
                                    Image(systemName: "xmark").imageScale(.small)
                                }
                                .font(Typography.secondary)
                                .padding(.horizontal, Spacing.m)
                                .padding(.vertical, Spacing.s)
                                .background(Palette.infoFill, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove tag \(name)"))
                        }
                    }
                }
            }
            TextField(text: $query) { Text("Add tag") }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { add(query) }
            ForEach(matches, id: \.id) { tag in
                Button { add(tag.name) } label: {
                    HStack {
                        Text(verbatim: tag.name).foregroundStyle(Palette.text)
                        Spacer()
                        Text(verbatim: "\(counts[tag.id] ?? 0)").foregroundStyle(Palette.textSecondary)
                    }
                    .font(Typography.body)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if canCreate {
                Button { add(query) } label: {
                    Label { Text("Create tag “\(query.trimmingCharacters(in: .whitespaces))”") } icon: { Image(systemName: "plus") }
                }
                .font(Typography.body)
            }
        }
    }

    private var key: String { TextKey.tagKey(query) }
    private var chosen: Set<String> { Set(tags.map(TextKey.tagKey)) }

    private var matches: [TagRow] {
        guard !key.isEmpty else { return [] }
        return available.filter { TextKey.tagKey($0.name).contains(key) && !chosen.contains(TextKey.tagKey($0.name)) }
    }

    private var canCreate: Bool {
        !key.isEmpty && !chosen.contains(key) && !available.contains { TextKey.tagKey($0.name) == key }
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        query = ""
        guard !TextKey.tagKey(trimmed).isEmpty, !chosen.contains(TextKey.tagKey(trimmed)) else { return }
        tags.append(trimmed)
    }
}
