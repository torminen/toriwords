import ToriCore
import ToriDictionary
import ToriStore

/// Add-screen autocomplete (§6.2 step 1): from the 2nd character, up to 3 "In your vocabulary" Entries, then dictionary
/// headwords whose keys are not already listed; 8 rows in total.
public enum Autocomplete {
    public enum Item: Hashable, Sendable {
        case vocabulary(VocabularyHit)
        case dictionary(Completion)
    }

    public static let total = 8
    public static let vocabularyLimit = 3

    public static func items(for input: String, store: ToriStore, dictionary: BundledDictionary?) throws -> [Item] {
        let key = TextKey.matchKey(input)
        guard key.count >= 2 else { return [] }
        let own = try store.read { try $0.vocabularyPrefix(key, limit: vocabularyLimit) }
        let fromDictionary = try dictionary?.autocomplete(
            prefix: key, excluding: Set(own.map(\.matchKey)), limit: total - own.count) ?? []
        return own.map(Item.vocabulary) + fromDictionary.map(Item.dictionary)
    }
}
