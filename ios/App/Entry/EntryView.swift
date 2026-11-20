import SwiftUI
import ToriCore
import ToriEnrichment
import ToriStore
import ToriUI

/// Entry read and edit mode.
/// `.entryEdit` (Review ••• Edit) opens straight in edit mode, and Done / Cancel return to the caller.
struct EntryView: View {
    let store: ToriStore
    let id: ToriID
    let editOnly: Bool

    @Environment(AppEnvironment.self) private var env
    @Environment(PendingDeletion.self) private var deletion
    @Environment(\.dismiss) private var dismiss

    @State private var detail: EntryDetail?
    @State private var loaded = false
    @State private var showCheckBanner = false
    @State private var draft: EntryDraft?
    @State private var suggestions: [Suggestion] = []
    @State private var allTags: [TagRow] = []
    @State private var tagCounts: [ToriID: Int] = [:]
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var mergeTarget: String?
    @State private var deletedHere = false
    @State private var deletedElsewhere = false
    @State private var retrying = false
    @State private var errorMessage: String?

    init(store: ToriStore, id: ToriID, editOnly: Bool = false) {
        self.store = store
        self.id = id
        self.editOnly = editOnly
    }

    private var isEditing: Bool { draft != nil }

    var body: some View {
        Group {
            if let detail {
                if let current = draft {
                    // Not Binding($draft): its force-unwrap traps when the form re-reads after draft = nil (Cancel/Done/Delete).
                    let binding = Binding(get: { draft ?? current }, set: { if draft != nil { draft = $0 } })
                    EntryEditForm(draft: binding, detail: detail, allTags: allTags, tagCounts: tagCounts) { confirmDelete = true }
                } else {
                    readMode(detail)
                }
            } else {
                Palette.background
            }
        }
        .navigationTitle(isEditing ? Text("Edit") : Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        // Edit mode is left only by Cancel or Done: hiding Back also disables the edge swipe (U11).
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { toolbar }
        .task { await observe() }
        .alert(Text("Discard changes?"), isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { endEditing() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert(Text("“\(mergeTarget ?? "")” is already in your vocabulary"), isPresented: Binding(
            get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } })) {
            Button("Merge") { save(merge: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Merge combines meanings, sentences, tags and review history into one word.")
        }
        .alert(Text("Delete “\(detail?.text ?? "")”?"), isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed with its review history on all your devices.")
        }
        .alert(Text("This word was deleted on another device"), isPresented: $deletedElsewhere) {
            Button("OK") { dismiss() }
        }
        .alert(Text("Something went wrong"), isPresented: Binding(get: { errorMessage != nil },
                                                                 set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let draft, let detail {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { if draft.hasChanges(from: detail) { confirmDiscard = true } else { endEditing() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { save(merge: false) }.fontWeight(.semibold).disabled(!draft.canSave)
            }
        } else if let detail {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { beginEditing(detail) }
                StatusMenu(status: detail.status, set: setStatus) { confirmDelete = true }
            }
        }
    }

    // MARK: Read mode

    private func readMode(_ e: EntryDetail) -> some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: e.text).font(Typography.cardWord)
                    SpeakButton(e.text, sentence: e.contexts.compactMap(\.sentence).first)
                    Spacer()
                    StageMarker(StageMarker.Kind(e.stage))
                }
                if let ipa = e.ipa, !ipa.isEmpty {
                    Text(verbatim: ipa).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
                if showCheckBanner {
                    Banner.checkTranslation { EmptyView() }
                }
            }

            meanings(e)

            let shown = Set(e.senses.compactMap(\.translation).map(TextKey.translationKey))
            let offered = suggestions.filter { s in s.sense.translation.map { !shown.contains(TextKey.translationKey($0)) } ?? false }
            if !offered.isEmpty {
                Section {
                    ForEach(offered, id: \.self) { s in
                        HStack {
                            VariantRow(s.sense.translation ?? "", isMachine: s.isMachine, isChecked: false) { addSuggested(s) }
                            Button("Add") { addSuggested(s) }.font(Typography.body.weight(.semibold))
                        }
                    }
                } header: {
                    Text("Suggested meanings")
                }
            }

            let sentences = e.contexts.filter { $0.sentence != nil || $0.sourceTitle != nil || $0.sourceURL != nil }
            if !sentences.isEmpty {
                Section {
                    ForEach(sentences, id: \.id) { c in sentenceRow(c, word: e.text) }
                } header: {
                    Text("Sentences")
                }
            }

            if !e.tags.isEmpty {
                Section {
                    Text(verbatim: e.tags.map(\.name).joined(separator: ", "))
                } header: {
                    Text("Tags")
                }
            }

            if let note = e.note, !note.isEmpty {
                Section { Text(verbatim: note) } header: { Text("Note") }
            }

            if !e.cards.isEmpty && e.status == .active {
                Section {
                    ForEach(e.cards, id: \.id) { card in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CardLabels.stage(card.stage))
                                if let next = NextReview.text(inDays: card.dueDay.map { $0 - Now.today }) {
                                    Text(next).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        } label: {
                            Text(CardLabels.direction(card.direction))
                        }
                    }
                } header: {
                    Text("Learning")
                }
            }

            Section { RelatedWords(word: e.text) }

            if e.senses.contains(where: { $0.translationSource == .wiktionary }) {
                Section { WiktionaryMark() }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func meanings(_ e: EntryDetail) -> some View {
        Section {
            ForEach(e.senses, id: \.id) { s in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: s.translation ?? "—").font(Typography.body.weight(.semibold))
                        if let pos = s.partOfSpeech {
                            Text(verbatim: pos).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    if let d = s.definition, !d.isEmpty {
                        Text(verbatim: d).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            switch e.translation {
            case .notFound:
                Banner(.warning, title: Text("No translation found — add your own"),
                       message: Text("Not reviewed until it has a translation.")) {
                    HStack(spacing: Spacing.l) {
                        Button("Add meaning") { beginEditing(e, addMeaning: true) }
                        Button("Try again") { tryAgain() }.disabled(retrying)
                    }
                }
            case .pending:
                Text("Translation pending").foregroundStyle(Palette.textSecondary)
            case .none:
                Button("Add meaning") { beginEditing(e, addMeaning: true) }
            case .has:
                EmptyView()
            }
        } header: {
            Text("Meanings")
        }
    }

    @ViewBuilder
    private func sentenceRow(_ c: EntryDetail.Context, word: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let sentence = c.sentence {
                HStack(alignment: .firstTextBaseline) {
                    SentenceText(sentence, highlight: c.highlight).font(Typography.body)
                    Spacer()
                    SpeakButton(sentence)
                }
            }
            if let label = c.sourceTitle ?? c.sourceURL.flatMap({ URL(string: $0)?.host() }) {
                if let url = c.sourceURL.flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true {
                    Link(destination: url) { Text(verbatim: "— \(label)") }.font(Typography.secondary)
                } else {
                    Text(verbatim: "— \(label)").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: Data

    private func observe() async {
        let id = self.id
        let observation = store.observe { r in try r.entry(id) }
        do {
            for try await value in observation {
                if !loaded, let value {
                    loaded = true
                    // Opening the entry clears "Check translation"; the banner stays for this visit.
                    showCheckBanner = value.needsCheck
                    if value.needsCheck { try? store.markChecked(value.id) }
                    if editOnly { beginEditing(value) }
                    Task { await loadSuggestions(value.text) }
                    allTags = (try? store.read { try $0.allTags() }) ?? []
                    tagCounts = (try? store.read { try $0.tagCounts() }) ?? [:]
                }
                if value == nil, loaded, !deletedHere {
                    deletedElsewhere = true
                }
                detail = value
            }
        } catch {}
    }

    private func loadSuggestions(_ text: String) async {
        suggestions = await env.enrichment?.suggestions(for: text) ?? []
    }

    private func beginEditing(_ e: EntryDetail, addMeaning: Bool = false) {
        var d = EntryDraft(e)
        if addMeaning { d.meanings.append(.init()) }
        draft = d
    }

    private func endEditing() {
        draft = nil
        if editOnly { dismiss() }
    }

    private func save(merge: Bool) {
        guard let draft, let detail else { return }
        do {
            switch try store.save(draft, original: detail, mergeIfDuplicate: merge) {
            case .saved:
                env.didChangeWords()
                // UQ-7 proposal: after Merge the merged word opens in read mode (the old ID resolves to it).
                endEditing()
                Task { await loadSuggestions(draft.text) }
            case .duplicate:
                mergeTarget = Capture.clean(draft.text).text
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func setStatus(_ status: EntryStatus) {
        guard let detail else { return }
        do {
            try store.setStatus([detail.id], status)
            env.didChangeWords()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func delete() {
        guard let detail else { return }
        deletedHere = true
        deletion.schedule([detail.id], word: detail.text)
        draft = nil
        dismiss()
    }

    private func addSuggested(_ s: Suggestion) {
        guard let detail else { return }
        do {
            try store.addSense(to: detail.id, s.sense)
            env.didChangeWords()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func tryAgain() {
        guard let detail, let enrichment = env.enrichment else { return }
        retrying = true
        Task {
            _ = try? await enrichment.tryAgain(detail.id)
            retrying = false
        }
    }
}

/// ••• on the entry: I already know this / Pause / Delete, or Resume learning.
struct StatusMenu: View {
    let status: EntryStatus
    let set: (EntryStatus) -> Void
    let delete: () -> Void

    var body: some View {
        Menu {
            if status == .active {
                Button("I already know this", systemImage: "checkmark") { set(.known) }
                Button("Pause", systemImage: "pause") { set(.paused) }
            } else {
                Button("Resume learning", systemImage: "arrow.clockwise") { set(.active) }
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("More"))
    }
}

enum CardLabels {
    static func direction(_ d: CardDirection) -> LocalizedStringResource {
        switch d {
        case .recognition: "English → Russian"
        case .recall: "Russian → English"
        case .cloze: "Fill in the blank"
        }
    }

    static func stage(_ s: CardStage) -> LocalizedStringResource {
        switch s {
        case .new: Strings.stageNew
        case .learning: Strings.stageLearning
        case .knownWell: Strings.stageKnownWell
        }
    }
}

// MARK: Edit mode

/// Contacts-style edit form: ⊖ delete and ≡ reorder on meanings, ⊕ Add meaning / Add sentence, tags, note, IPA,
/// Delete word.
private struct EntryEditForm: View {
    @Binding var draft: EntryDraft
    let detail: EntryDetail
    let allTags: [TagRow]
    let tagCounts: [ToriID: Int]
    let delete: () -> Void

    var body: some View {
        List {
            Section {
                TextField(text: $draft.text) { Text("Word or phrase") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Typography.heading)
                TextField(text: $draft.ipa) { Text("IPA") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                ForEach($draft.meanings) { $m in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextField(text: $m.translation) { Text("Translation") }
                        TextField(text: $m.partOfSpeech) { Text("Part of speech") }
                            .font(Typography.secondary)
                        TextField(text: $m.definition, axis: .vertical) { Text("Definition") }
                            .font(Typography.secondary)
                    }
                }
                .onDelete { draft.meanings.remove(atOffsets: $0) }
                .onMove { draft.meanings.move(fromOffsets: $0, toOffset: $1) }
                Button { draft.meanings.append(.init()) } label: {
                    Label { Text("Add meaning") } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(Palette.success) }
                }
            } header: {
                Text("Meanings")
            }

            Section {
                ForEach($draft.sentences) { $s in
                    if s.context == nil {
                        VStack(alignment: .leading) {
                            TextField(text: $s.text, axis: .vertical) { Text("Sentence") }
                            TextField(text: Binding(get: { s.source ?? "" }, set: { s.source = $0 })) { Text("Source (optional)") }
                                .font(Typography.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: s.text)
                            if let source = s.source {
                                Text(verbatim: "— \(source)").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
                .onDelete { draft.sentences.remove(atOffsets: $0) }
                Button { draft.sentences.append(.init()) } label: {
                    Label { Text("Add sentence") } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(Palette.success) }
                }
            } header: {
                Text("Sentences")
            }

            Section {
                TagEditor(tags: $draft.tags, available: allTags, counts: tagCounts)
            } header: {
                Text("Tags")
            }

            Section {
                TextField(text: $draft.note, axis: .vertical) { Text("Note") }
            } header: {
                Text("Note")
            }

            Section {
                Button("Delete word", role: .destructive, action: delete)
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }
}
