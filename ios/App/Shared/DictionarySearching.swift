import ToriEnrichment

/// App-side seam for the ToriDictionary searches Add and the Entry screen need (§6.2 items 1–3, 8). The real adapter is
/// wired in `AppEnvironment.dictionarySearch` once ToriDictionary lands; until then `NoDictionarySearch` returns nothing,
/// which the screens handle as "not in the dictionary".
protocol DictionarySearching: Sendable {
    /// Headwords whose key starts with the typed key, phrases included, by frequency (§6.2 item 1b).
    func complete(_ prefix: String, limit: Int) -> [Completion]
    /// English candidates for Russian input (P1, §6.2 item 2).
    func reverse(_ russian: String, limit: Int) -> [Completion]
    /// The base form when the text is a listed inflected form ("took" → "take"); nil for phrases (P1, PD-14).
    func baseForm(of text: String) -> String?
    /// Dictionary phrases contained in a longer text ("took off" in a sentence → "take off", §6.2 item 3).
    func containedPhrases(in text: String) -> [String]
    /// Up to `limit` related words with their primary translation (P1, §6.2 item 8).
    func related(to text: String, limit: Int) -> [Completion]
}

struct NoDictionarySearch: DictionarySearching {
    func complete(_ prefix: String, limit: Int) -> [Completion] { [] }
    func reverse(_ russian: String, limit: Int) -> [Completion] { [] }
    func baseForm(of text: String) -> String? { nil }
    func containedPhrases(in text: String) -> [String] { [] }
    func related(to text: String, limit: Int) -> [Completion] { [] }
}
