import SwiftUI
import ToriCore
import ToriEnrichment
import ToriStore
import ToriUI

/// Add screen.
struct AddView: View {
    let store: ToriStore
    let initialText: String?
    @Environment(AppEnvironment.self) private var env
    @State private var model: AddModel?

    var body: some View {
        Group {
            if let model { AddContent(model: model) } else { Palette.background }
        }
        .task {
            if model == nil { model = AddModel(store: store, env: env, text: initialText) }
        }
    }
}

private struct AddContent: View {
    @Bindable var model: AddModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false

    var body: some View {
        Group {
            switch model.step {
            case .typing: TypingStep(model: model)
            case .preview: PreviewStep(model: model)
            }
        }
        .background(Palette.background)
        .navigationTitle(Text("Add"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                switch model.step {
                case .typing:
                    Button("Cancel") {
                        if model.text.trimmingCharacters(in: .whitespaces).isEmpty { dismiss() } else { confirmDiscard = true }
                    }
                case .preview:
                    Button { model.backToTyping() } label: {
                        Label { Text("Back") } icon: { Image(systemName: "chevron.backward") }.labelStyle(.titleAndIcon)
                    }
                }
            }
            if model.step == .preview {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { model.save() }.fontWeight(.semibold).disabled(!model.canSave)
                }
            }
        }
        .confirmationDialog(Text("Discard this word?"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert(Text("Something went wrong"), isPresented: Binding(get: { model.errorMessage != nil },
                                                                 set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }
}

// MARK: Typing

private struct TypingStep: View {
    @Bindable var model: AddModel
    @Environment(Router.self) private var router
    @FocusState private var focused: Bool
    @State private var chipRange: ClosedRange<Int>?

    var body: some View {
        List {
            Section {
                TextField(text: $model.text) { Text("Add a word…") }
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { Task { await model.showPreview(for: model.text) } }
                    .font(Typography.body)
            } footer: {
                if model.savedWord != nil, model.text.isEmpty {
                    Label { Text("Saved") } icon: { Image(systemName: "checkmark.circle.fill") }
                        .foregroundStyle(Palette.success).font(Typography.secondary)
                }
            }

            if model.looksLikeSentence {
                sentencePicker
            } else if model.russianWithoutCandidates {
                Text("Type the English word or phrase").foregroundStyle(Palette.textSecondary)
            } else if !model.completions.isEmpty {
                Section {
                    ForEach(model.completions, id: \.text) { completionRow($0) }
                }
            } else if let word = model.savedWord, model.text.isEmpty {
                Section { RelatedWords(word: word, title: Text("Related to “\(word)”")) }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear { focused = true }
        .onChange(of: model.text) { chipRange = nil }
    }

    private func completionRow(_ c: Completion) -> some View {
        Button {
            if let id = c.entry { router.push(.entry(id)) } else { Task { await model.showPreview(for: c.text) } }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: c.text).font(Typography.body.weight(.semibold)).foregroundStyle(Palette.text)
                    if let pos = c.partOfSpeech {
                        Text(verbatim: pos).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    if c.entry != nil { Badge("In your vocabulary", fill: Palette.infoFill, ink: Palette.accent) }
                }
                if let t = c.translation {
                    Text(verbatim: t).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A typed sentence: tap one word, or adjacent words for a phrase (as in capture).
    private var sentencePicker: some View {
        Section {
            if !model.containedPhrases.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(model.containedPhrases, id: \.self) { phrase in
                            Chip(Text(verbatim: phrase), isSelected: false) { Task { await model.pickPhrase(phrase) } }
                        }
                    }
                }
            }
            FlowLayout(spacing: Spacing.s) {
                ForEach(Array(model.sentenceChips.enumerated()), id: \.offset) { i, word in
                    Chip(Text(verbatim: word), isSelected: chipRange?.contains(i) == true) { tap(i) }
                }
            }
            if let range = chipRange {
                Button("Continue") { Task { await model.pick(firstChip: range.lowerBound, lastChip: range.upperBound) } }
                    .buttonStyle(.toriPrimary)
            }
        } header: {
            Text("Tap the word to save")
        } footer: {
            Text("The text is kept as the sentence.")
        }
    }

    /// First tap picks a word; a tap next to the selection extends it; any other tap starts again.
    private func tap(_ i: Int) {
        guard let r = chipRange else { chipRange = i...i; return }
        if i == r.lowerBound - 1 { chipRange = i...r.upperBound }
        else if i == r.upperBound + 1 { chipRange = r.lowerBound...i }
        else if r == i...i { chipRange = nil }
        else { chipRange = i...i }
    }
}

// MARK: Preview

private struct PreviewStep: View {
    @Bindable var model: AddModel
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var allTags: [TagRow] = []
    @State private var tagCounts: [ToriID: Int] = [:]

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: model.draft.text).font(Typography.cardWord)
                    SpeakButton(model.draft.text, sentence: model.draft.sentence.isEmpty ? nil : model.draft.sentence)
                    Spacer()
                }
                let pos = model.draft.variants.compactMap(\.sense.partOfSpeech).first
                let detail = [model.ipa, pos].compactMap { $0 }
                if !detail.isEmpty {
                    Text(verbatim: detail.joined(separator: " · ")).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
                if let forms = model.baseForm {
                    baseFormPicker(forms)
                }
            }

            if let existing = model.existing {
                Section { existingBanner(existing) }
            }

            Section {
                if model.isLoading {
                    ProgressView()
                } else if model.draft.variants.isEmpty {
                    Text("No suggestions: the word is not in the dictionary, and on-device translation isn't available. Type a translation (optional).")
                        .font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
                ForEach(Array(model.draft.variants.enumerated()), id: \.offset) { i, v in
                    VariantRow(v.sense.translation ?? "", isMachine: v.isMachine, isChecked: v.isChecked,
                               isDisabled: v.isExisting) { model.draft.toggle(i) }
                }
                TextField(text: $model.draft.ownTranslation) { Text("Type a translation (optional)") }
            } header: {
                Text("Translation")
            }

            let definitions = model.draft.variants.filter(\.isChecked).compactMap(\.sense.definition)
            if !definitions.isEmpty {
                Section {
                    ForEach(Array(Set(definitions)).sorted(), id: \.self) { Text(verbatim: $0).font(Typography.body) }
                } header: {
                    Text("Definition")
                }
            }

            Section {
                TextField(text: $model.draft.sentence, axis: .vertical) { Text("Sentence (optional)") }
                    .onChange(of: model.draft.sentence) { model.sentenceChanged() }
                if let help = model.contextHelp {
                    Text("In this sentence: \(help)").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
                TextField(text: $model.draft.source) { Text("Source (optional)") }
            }

            Section {
                TagEditor(tags: $model.draft.tags, available: allTags, counts: tagCounts)
            } header: {
                Text("Tags")
            }
        }
        .listStyle(.insetGrouped)
        .task {
            allTags = (try? env.store?.read { try $0.allTags() }) ?? []
            tagCounts = (try? env.store?.read { try $0.tagCounts() }) ?? [:]
        }
    }

    private func baseFormPicker(_ forms: (base: String, typed: String)) -> some View {
        Picker(selection: Binding(get: { model.draft.text }, set: { w in Task { await model.useForm(w) } })) {
            Text(verbatim: forms.base).tag(forms.base)
            Text(verbatim: forms.typed).tag(forms.typed)
        } label: {
            Text("Save as")
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func existingBanner(_ existing: AddModel.Existing) -> some View {
        switch existing.status {
        case .active:
            Banner(.info, title: Text("Already in your vocabulary"),
                   message: Text("Save adds newly checked meanings and the sentence.")) {
                Button("Open word") { router.push(.entry(existing.id)) }
            }
        case .known, .paused:
            Banner(.info, title: existing.status == .known ? Text("You marked this as known") : Text("You paused this word"),
                   message: Text("Save adds the sentence and meanings.")) {
                Toggle(isOn: $model.resumeLearning) { Text("Resume learning") }
            }
        }
    }
}

/// Wraps chips onto as many lines as needed (sentence word chips).
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
