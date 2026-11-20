import Foundation
import Observation
import ToriCore
import ToriDictionary
import ToriShared

/// Capture sheet state: text and chips (`CaptureDraft`), dictionary variants, duplicate hint,
/// source, tags; Save writes one inbox file. No `user.sqlite`, no network, no Keychain.
@MainActor @Observable
final class ShareModel {
    let payload: SharePayload
    private(set) var draft: CaptureDraft
    private(set) var ipa: String?
    private(set) var variants: [Variant] = []
    var picked: Set<Variant> = []
    var typedTranslation = ""
    /// The existing Entry for the term ("Already in your vocabulary"), from `vocab-index.json`.
    private(set) var existing: VocabIndex.Entry?
    var resume = false
    var sourceTitle: String
    var tagsText: String
    private(set) var tagSuggestions: [String] = []
    let showTip: Bool
    private(set) var saved = false
    private(set) var saveFailed = false

    @ObservationIgnored private let group: AppGroup?
    @ObservationIgnored private let sticky: CaptureSticky?
    @ObservationIgnored private let finish: (Bool) -> Void
    /// Opened per capture from the containing app's bundle, read-only `immutable=1`.
    @ObservationIgnored private lazy var dictionary: BundledDictionary? =
        BundledDictionary.bundledURL().flatMap { try? BundledDictionary(path: $0.path) }
    @ObservationIgnored private lazy var index: VocabIndex? = try? group?.readVocabIndex()
    @ObservationIgnored private var lookedUp: String?

    init(payload: SharePayload, group: AppGroup?, finish: @escaping (Bool) -> Void) {
        self.payload = payload
        self.group = group
        self.finish = finish
        draft = CaptureDraft(payload)
        sticky = try? group?.readCaptureSticky()
        let offered = sticky?.offered(now: Self.nowMs) ?? (sourceTitle: nil, tags: [])
        sourceTitle = payload.title ?? offered.sourceTitle ?? ""
        tagsText = offered.tags.joined(separator: ", ")
        showTip = sticky?.tipShown != true
        if showTip { try? group?.writeCaptureSticky(.tipShown(previous: sticky)) }
        refresh()
    }

    var term: String? { draft.term }
    /// The text Save stores: the captured term or the dictionary offer chosen for it (base form / phrase).
    var entryText: String? { draft.entryText }
    var isNonLatin: Bool { !draft.cleaned.text.isEmpty && !draft.cleaned.isSaveable }
    var canSave: Bool { draft.canSave && !saved }
    var hasDictionary: Bool { dictionary != nil }

    func editText(_ text: String) { draft.editText(text); refresh() }
    func tapChip(_ i: Int) { draft.tapChip(i); refresh() }
    func editSentence(_ text: String) { draft.editSentence(text) }
    /// Picks a dictionary offer as the saved text (nil = the captured text); variants follow the saved text.
    func saveAs(_ text: String?) { draft.saveAs(text); lookUp() }

    func toggle(_ v: Variant) {
        if picked.contains(v) { picked.remove(v) } else { picked.insert(v) }
    }

    /// New term (the draft dropped its offers): base form / contained phrases, then the lookup.
    private func refresh() {
        let r = draft.term.flatMap { try? dictionary?.resolve($0) }
        draft.setOffers(baseForm: r?.baseForms.first?.headword.text, phrases: r?.containedPhrases.map(\.text) ?? [])
        lookUp()
    }

    /// New saved text: dictionary variants (first preselected) and the duplicate hint.
    private func lookUp() {
        guard let term = draft.entryText else {
            (ipa, variants, picked, existing, lookedUp) = (nil, [], [], nil, nil)
            return
        }
        let key = TextKey.matchKey(term)
        guard key != lookedUp else { return }
        lookedUp = key
        let headwords = (try? dictionary?.headwords(key: key)) ?? []
        ipa = headwords.lazy.compactMap(\.ipa).first
        variants = Variant.of(headwords)
        picked = variants.first.map { [$0] } ?? []
        existing = index?.entry(matching: term)
        resume = false
        tagSuggestions = TagInput.suggestions(sticky: sticky?.offered(now: Self.nowMs).tags ?? [], index: index?.tags ?? [])
    }

    func addTag(_ name: String) {
        tagsText = TagInput.names(tagsText + "," + name).joined(separator: ", ")
    }

    /// Save: inbox file (atomic) → sticky → Darwin notification → dismiss after a short "Saved".
    func save() {
        guard let group else { saveFailed = true; return }
        let now = Self.nowMs
        let version = dictionary?.version
        let chosen = variants.filter(picked.contains).map { v in
            InboxFile.ChosenSense(translation: v.translation, definition: v.glossEn, pos: v.partOfSpeech,
                                  provenance: .init(kind: "wiktionary", dictVersion: version, headwordKey: v.headwordKey,
                                                    senseOrdinal: v.senseOrdinal))
        }
        let tags = TagInput.names(tagsText)
        var rng = SystemRandomNumberGenerator()
        guard let file = draft.inboxFile(captureId: ToriID.v7(unixMs: now, using: &rng), capturedAt: now,
                                         utcOffsetMin: TimeZone.current.secondsFromGMT() / 60, payload: payload,
                                         sourceTitle: sourceTitle, tags: tags, chosenSenses: chosen,
                                         typedTranslation: variants.isEmpty ? typedTranslation : nil, resume: resume)
        else { return }
        do {
            try group.inbox.write(file)
        } catch {
            saveFailed = true
            return
        }
        try? group.writeCaptureSticky(.afterSave(now: now, sourceTitle: sourceTitle, tags: tags,
                                                 previous: (try? group.readCaptureSticky()) ?? sticky))
        InboxNotification.post()
        saved = true
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            finish(true)
        }
    }

    func cancel() { finish(false) }
    func clearSaveFailed() { saveFailed = false }

    static var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
