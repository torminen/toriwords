import Foundation
import Observation
import ToriCore
import ToriEnrichment
import ToriStore

/// Add: typing with autocomplete, then the preview, then Save and clear for the next word.
@MainActor @Observable
final class AddModel {
    enum Step: Equatable { case typing, preview }

    /// What the saved Entry with the same key looks like (it may be known or paused).
    struct Existing: Equatable {
        var id: ToriID
        var status: EntryStatus
    }

    private(set) var step: Step = .typing
    var text: String { didSet { if text != oldValue { refreshCompletions() } } }
    private(set) var completions: [Completion] = []
    private(set) var russianWithoutCandidates = false
    /// Word chips of a typed sentence and the dictionary phrases found in it (more than 6 words or sentence punctuation).
    private(set) var sentenceChips: [String] = []
    private(set) var containedPhrases: [String] = []

    var draft = AddDraft(text: "")
    private(set) var existing: Existing?
    var resumeLearning = false
    private(set) var ipa: String?
    /// "Did you mean …?": the base form is preselected, the typed form stays available.
    private(set) var baseForm: (base: String, typed: String)?
    private(set) var isLoading = false
    private(set) var contextHelp: String?
    /// The last saved word: "Saved" and Related to "<word>" under the field.
    private(set) var savedWord: String?
    var errorMessage: String?

    private let store: ToriStore
    private let env: AppEnvironment
    @ObservationIgnored private var helpTask: Task<Void, Never>?

    init(store: ToriStore, env: AppEnvironment, text: String?) {
        self.store = store
        self.env = env
        self.text = text ?? ""
        refreshCompletions()
    }

    var looksLikeSentence: Bool { AddDraft(text: text).looksLikeSentence }

    // MARK: Typing

    private func refreshCompletions() {
        russianWithoutCandidates = false
        let typed = AddDraft(text: text)
        if typed.looksLikeSentence {
            completions = []
            let cleaned = Capture.clean(text).text
            let scalars = Array(cleaned.unicodeScalars)
            sentenceChips = Capture.chips(cleaned).map { String(String.UnicodeScalarView(scalars[$0.start..<$0.end])) }
            containedPhrases = env.dictionarySearch.containedPhrases(in: text)
            return
        }
        sentenceChips = []
        containedPhrases = []
        switch Autocomplete.classify(text) {
        case .tooShort:
            completions = []
        case .russian(let ru):
            completions = env.dictionarySearch.reverse(ru, limit: Autocomplete.totalLimit)
            russianWithoutCandidates = completions.isEmpty
        case .english(let en):
            let saved = (try? store.read { try $0.vocabularyMatches(prefix: en, limit: Autocomplete.vocabularyLimit) }) ?? []
            let vocabulary = saved.map { row in
                Completion(text: row.text, translation: { if case .has(let t) = row.translation { t } else { nil } }(), entry: row.id)
            }
            completions = Autocomplete.merge(vocabulary: vocabulary,
                                             dictionary: env.dictionarySearch.complete(en, limit: Autocomplete.totalLimit))
        }
    }

    /// "Tap the word to save" on a typed sentence: chips `first...last` become the word, the sentence its context.
    func pick(firstChip: Int, lastChip: Int) async {
        var d = AddDraft(text: text)
        d.pick(firstChip: firstChip, lastChip: lastChip)
        await showPreview(for: d.text, sentence: d.sentence)
    }

    /// A contained dictionary phrase picked from a typed sentence: saved as the phrase, with the sentence kept.
    func pickPhrase(_ phrase: String) async {
        await showPreview(for: phrase, sentence: Capture.clean(text).text)
    }

    // MARK: Preview

    func showPreview(for word: String, sentence: String = "") async {
        let typed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddDraft(text: typed).canSave else { return }
        if !TextKey.isPhrase(typed), let base = env.dictionarySearch.baseForm(of: typed),
           TextKey.matchKey(base) != TextKey.matchKey(typed) {
            baseForm = (base, typed)
            await load(base, sentence: sentence)
        } else {
            baseForm = nil
            await load(typed, sentence: sentence)
        }
        step = .preview
    }

    /// Switches between the base form and the typed form (keeps sentence, source, tags and the own translation).
    func useForm(_ word: String) async {
        await load(word, sentence: draft.sentence)
    }

    private func load(_ word: String, sentence: String) async {
        isLoading = true
        defer { isLoading = false }
        var d = AddDraft(text: word)
        d.sentence = sentence.isEmpty ? draft.sentence : sentence
        d.source = draft.source
        d.tags = draft.tags
        d.ownTranslation = draft.ownTranslation
        let saved = try? store.read { r in try r.entryID(matching: word).flatMap { try r.entry($0) } }
        existing = saved.map { Existing(id: $0.id, status: $0.status) }
        resumeLearning = false
        let suggestions = await env.enrichment?.suggestions(for: word) ?? []
        if let savedIPA = saved?.ipa { ipa = savedIPA } else { ipa = await env.enrichment?.ipa(for: word) }
        d.setSuggestions(suggestions, existing: saved?.senses.compactMap(\.translation) ?? [], existingEntry: saved?.id)
        draft = d
        sentenceChanged()
    }

    /// ‹ Back: to typing with the text kept, no prompt (U10).
    func backToTyping() {
        helpTask?.cancel()
        step = .typing
    }

    /// Debounced "In this sentence: …" (P1): never stored.
    func sentenceChanged() {
        helpTask?.cancel()
        contextHelp = nil
        let sentence = draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, let enrichment = env.enrichment else { return }
        helpTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let help = await enrichment.contextHelp(for: sentence)
            guard !Task.isCancelled else { return }
            self?.contextHelp = help
        }
    }

    // MARK: Save

    var canSave: Bool { draft.canSave }

    func save() {
        guard canSave else { return }
        do {
            let input = draft.captureInput(now: Now.ms)
            let id = try store.capture(input)
            if resumeLearning { try store.setStatus([id], .active) }
            // Dictionary IPA is automatic (rank 0): it never overwrites an IPA the user typed.
            if let ipa, existing?.id == nil { try store.setEntryIPA(id, ipa, rank: .automatic) }
            savedWord = input.term
            env.didChangeWords()
            if input.senses.isEmpty, let enrichment = env.enrichment { Task { _ = try? await enrichment.runPending() } }
            helpTask?.cancel()
            draft = AddDraft(text: "")
            existing = nil
            baseForm = nil
            ipa = nil
            contextHelp = nil
            text = ""
            step = .typing
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
