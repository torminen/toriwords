import SwiftUI
import ToriDictionary
import ToriShared
import ToriUI

/// The capture sheet (UI doc §3.3, wireframes 1-10 iOS 8, 8-6 C1–C4): Cancel · ToriWords · Save.
struct ShareSheetView: View {
    @Bindable var model: ShareModel
    @State private var text = ""
    @State private var sentence = ""
    @State private var tagsOpen = false

    var body: some View {
        NavigationStack {
            Form {
                if model.showTip { tip }
                textSection
                if model.term != nil {
                    hintSection
                    translationSection
                }
                sourceSection
                tagsSection
            }
            .navigationTitle("ToriWords")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.save() }.disabled(!model.canSave).bold()
                }
            }
            .overlay { if model.saved { savedBadge } }
            .alert("Could not save. Open ToriWords once, then try again.", isPresented: $model.saveFailedBinding) {}
        }
        .tint(Palette.accent)
        .onAppear {
            text = model.draft.cleaned.text
            sentence = model.draft.sentence ?? ""
        }
    }

    private var tip: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Tip: put ToriWords first").font(.headline)
                Text("In the share menu, scroll the app row to More → Edit and drag ToriWords to the top.")
                    .font(.subheadline)
            }
            .listRowBackground(Palette.tip)
        }
    }

    @ViewBuilder private var textSection: some View {
        if model.draft.isSentenceSource {
            Section {
                ChipFlow(chips: model.draft.chips, selection: model.draft.selection, tap: model.tapChip)
                if let term = model.term { heading(term) }
            } header: {
                Text("Tap the word to save")
            }
        } else {
            Section {
                TextField("Word or phrase", text: $text, axis: .vertical)
                    .font(Typography.heading)
                    .onChange(of: text) { _, new in model.editText(new) }
                if model.isNonLatin {
                    Text("ToriWords saves English words and phrases").font(.subheadline).foregroundStyle(Palette.danger)
                }
                if let ipa = model.ipa { Text(verbatim: "/\(ipa)/").foregroundStyle(Palette.textSecondary) }
                TextField("Sentence (optional)", text: $sentence, axis: .vertical)
                    .onChange(of: sentence) { _, new in model.editSentence(new) }
            }
        }
    }

    private func heading(_ term: String) -> some View {
        HStack(spacing: Spacing.s) {
            Text(term).font(Typography.heading)
            if let ipa = model.ipa { Text(verbatim: "/\(ipa)/").foregroundStyle(Palette.textSecondary) }
        }
    }

    @ViewBuilder private var hintSection: some View {
        if let existing = model.existing {
            Section {
                switch existing.status {
                case .active:
                    Text("Already in your vocabulary").font(.headline)
                case .known, .paused:
                    Text(existing.status == .known ? "You marked this as known" : "You paused this word").font(.headline)
                    Toggle("Resume learning", isOn: $model.resume)
                }
                if !existing.translations.isEmpty {
                    Text(existing.translations.prefix(3).joined(separator: ", ")).foregroundStyle(Palette.textSecondary)
                }
                Text("Save adds this sentence and source.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            .listRowBackground(Palette.infoFill)
        }
    }

    @ViewBuilder private var translationSection: some View {
        if model.variants.isEmpty {
            Section {
                Text(model.hasDictionary ? "Not in the dictionary" : "The dictionary is ready after you open ToriWords once")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
                TextField("Translation (optional)", text: $model.typedTranslation)
            } header: {
                Text("Translation")
            } footer: {
                Text("Without a translation the word is saved as \"Translation pending\".")
            }
        } else {
            Section {
                ForEach(model.variants, id: \.self) { v in
                    Button { model.toggle(v) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: model.picked.contains(v) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(model.picked.contains(v) ? Palette.accent : Palette.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.translation).foregroundStyle(Palette.text)
                                if let gloss = v.glossEn {
                                    Text(verbatim: "\(v.partOfSpeech) · \(gloss)").font(.footnote)
                                        .foregroundStyle(Palette.textSecondary).lineLimit(2)
                                }
                            }
                        }
                    }
                    .accessibilityAddTraits(model.picked.contains(v) ? .isSelected : [])
                }
            } header: {
                Text("Translation · Wiktionary")
            }
        }
    }

    private var sourceSection: some View {
        Section {
            TextField(model.payload.domain ?? String(localized: "Source title"), text: $model.sourceTitle)
            if let label = model.payload.sourceLabel {
                Text(verbatim: label).font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        } header: {
            Text("Source")
        }
    }

    private var tagsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $tagsOpen) {
                TextField("work, travel", text: $model.tagsText)
                    .textInputAutocapitalization(.never)
                if !model.tagSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(model.tagSuggestions, id: \.self) { name in
                                Button(name) { model.addTag(name) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Tags")
                    Spacer()
                    Text(model.tagsText).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
        }
    }

    private var savedBadge: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.m)
            .background(.regularMaterial, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private extension ShareModel {
    var saveFailedBinding: Bool {
        get { saveFailed }
        set { if !newValue { clearSaveFailed() } }
    }
}

/// Word chips, wrapped like text; picked chips are blue.
struct ChipFlow: View {
    let chips: [String]
    let selection: ClosedRange<Int>?
    let tap: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: Spacing.xs) {
            ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
                let on = selection?.contains(i) == true
                Button { tap(i) } label: {
                    Text(chip)
                        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
                        .foregroundStyle(on ? Color.white : Palette.text)
                        .background(on ? Palette.accent : Palette.neutralFill, in: RoundedRectangle(cornerRadius: Radius.chip))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var y: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
