import Foundation
import ToriCore

/// Entry edit mode (Product §5.7, doc 35 §3.5): the editable copy of an Entry and the writes Done makes.
public struct EntryDraft: Equatable, Sendable {
    public struct Meaning: Equatable, Sendable, Identifiable {
        /// Row identity in the editor (new rows have no Sense yet).
        public let id: UUID
        public var sense: ToriID?
        public var translation: String
        public var definition: String
        public var partOfSpeech: String

        public init(sense: ToriID? = nil, translation: String = "", definition: String = "", partOfSpeech: String = "") {
            id = UUID()
            self.sense = sense
            self.translation = translation
            self.definition = definition
            self.partOfSpeech = partOfSpeech
        }

        /// Content equality: the row identity does not count as a change.
        public static func == (a: Meaning, b: Meaning) -> Bool {
            a.sense == b.sense && a.translation == b.translation && a.definition == b.definition && a.partOfSpeech == b.partOfSpeech
        }

        var isBlank: Bool { [translation, definition].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    /// Existing sentences can only be removed (no Context edit API); new ones are added with a typed highlight.
    public struct Sentence: Equatable, Sendable, Identifiable {
        public let id: UUID
        public var context: ToriID?
        public var text: String
        public var source: String?

        public init(context: ToriID? = nil, text: String = "", source: String? = nil) {
            id = UUID()
            self.context = context
            self.text = text
            self.source = source
        }

        public static func == (a: Sentence, b: Sentence) -> Bool { a.context == b.context && a.text == b.text }
    }

    public var text: String
    public var ipa: String
    public var note: String
    public var meanings: [Meaning]
    public var sentences: [Sentence]
    public var tags: [String]

    public init(_ e: EntryDetail) {
        text = e.text
        ipa = e.ipa ?? ""
        note = e.note ?? ""
        meanings = e.senses.map { Meaning(sense: $0.id, translation: $0.translation ?? "", definition: $0.definition ?? "",
                                          partOfSpeech: $0.partOfSpeech ?? "") }
        sentences = e.contexts.filter { $0.sentence != nil }.map {
            Sentence(context: $0.id, text: $0.sentence ?? "", source: $0.sourceTitle ?? $0.sourceURL)
        }
        tags = e.tags.map(\.name)
    }

    /// "Discard changes?" only when something differs; blank new rows are not a change.
    public func hasChanges(from e: EntryDetail) -> Bool {
        var trimmed = self
        trimmed.meanings.removeAll { $0.sense == nil && $0.isBlank }
        trimmed.sentences.removeAll { $0.context == nil && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return trimmed != EntryDraft(e)
    }

    /// Done needs some text that can be a word (Latin letters, §5.2).
    public var canSave: Bool { Capture.clean(text).isSaveable }
}

private func nonEmpty(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

extension ToriStore {
    /// Applies an edit. A text that equals another Entry returns `.duplicate` before anything is written; call again with
    /// `mergeIfDuplicate` after the user confirms Merge (§5.3). The Entry ID stays valid: reads resolve a merged ID.
    public func save(_ d: EntryDraft, original e: EntryDetail, mergeIfDuplicate: Bool = false) throws -> KeyEditResult {
        let text = Capture.clean(d.text).text
        if text != e.text {
            let result = try setEntryText(e.id, text, mergeIfDuplicate: mergeIfDuplicate)
            if result != .saved { return result }
        }
        if nonEmpty(d.ipa) != e.ipa { try setEntryIPA(e.id, nonEmpty(d.ipa)) }
        if nonEmpty(d.note) != e.note { try setEntryNote(e.id, nonEmpty(d.note)) }

        // Meanings: delete, edit, add, then renumber when the order changed.
        let kept = Set(d.meanings.compactMap(\.sense))
        for s in e.senses where !kept.contains(s.id) { try deleteSense(s.id) }
        var order: [ToriID] = []
        for m in d.meanings {
            if let id = m.sense {
                if let old = e.senses.first(where: { $0.id == id }),
                   (old.translation ?? "", old.definition ?? "", old.partOfSpeech ?? "") != (m.translation, m.definition, m.partOfSpeech) {
                    try editSense(id, translation: nonEmpty(m.translation), definition: nonEmpty(m.definition),
                                  partOfSpeech: nonEmpty(m.partOfSpeech))
                }
                order.append(id)
            } else if !m.isBlank {
                order.append(try addSense(to: e.id, NewSense(translation: nonEmpty(m.translation), definition: nonEmpty(m.definition),
                                                            partOfSpeech: nonEmpty(m.partOfSpeech))))
            }
        }
        // New Senses are appended; renumber only when the edited order differs from "kept in old order, then new".
        let natural = e.senses.map(\.id).filter(kept.contains) + order.filter { !kept.contains($0) }
        if order != natural {
            for (i, id) in order.enumerated() { try moveSense(id, to: Double(i + 1)) }
        }

        // Sentences: delete removed ones, add new ones.
        let keptContexts = Set(d.sentences.compactMap(\.context))
        for c in e.contexts where c.sentence != nil && !keptContexts.contains(c.id) { try deleteContext(c.id) }
        for s in d.sentences where s.context == nil {
            guard let sentence = nonEmpty(s.text) else { continue }
            try addContext(to: e.id, sentence: sentence, highlight: Capture.typedHighlight(sentence: sentence, entryText: text),
                           source: nonEmpty(s.source ?? "").map { SourceInput(kind: .other, title: $0) }, capturedAt: clock())
        }

        // Tags by tag key.
        let wanted = Set(d.tags.map(TextKey.tagKey))
        for t in e.tags where !wanted.contains(TextKey.tagKey(t.name)) { try untag(e.id, tag: t.id) }
        let have = Set(e.tags.map { TextKey.tagKey($0.name) })
        for name in d.tags where !have.contains(TextKey.tagKey(name)) && !TextKey.tagKey(name).isEmpty { try tag([e.id], name: name) }
        return .saved
    }
}
