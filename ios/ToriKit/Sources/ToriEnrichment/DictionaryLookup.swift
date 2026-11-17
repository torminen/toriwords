// ToriEnrichment: enrichment orchestrator, Apple Translation adapter, TTS player (doc 36 §2.3, §6, §9).

/// What enrichment needs from the bundled dictionary (doc 36 §8.2). `ToriDictionary` conforms to it.
public protocol DictionaryLookup: Sendable {
    /// `meta.dictionary_version`, e.g. `2026.11.1`; stored as Sense provenance.
    var version: String { get }
    /// Exact `headword.key = key` hits (key = `TextKey.matchKey`), several POS possible, in dictionary order
    /// (`freq_rank` ascending NULL last, then `key`, then `id`). Empty when there is no hit.
    func lookup(key: String) throws -> [DictionaryHeadword]
}

public struct DictionaryHeadword: Hashable, Sendable {
    public var text: String
    /// `headword.key`; stored as `dict_headword_key`.
    public var key: String
    public var partOfSpeech: String?
    public var ipa: String?
    /// Ordered by `sense.ordinal`.
    public var senses: [DictionarySense]

    public init(text: String, key: String, partOfSpeech: String?, ipa: String?, senses: [DictionarySense]) {
        self.text = text
        self.key = key
        self.partOfSpeech = partOfSpeech
        self.ipa = ipa
        self.senses = senses
    }
}

public struct DictionarySense: Hashable, Sendable {
    /// `sense.ordinal`, stable within a build; stored as `dict_sense_ordinal`.
    public var ordinal: Int
    public var glossEn: String?
    /// `translation_ru.text` tied to this sense, ordered by `rank` (not yet deduplicated).
    public var translationsRu: [String]

    public init(ordinal: Int, glossEn: String?, translationsRu: [String]) {
        self.ordinal = ordinal
        self.glossEn = glossEn
        self.translationsRu = translationsRu
    }
}

/// Machine translation EN→RU (Apple Translation on iOS; a fake in tests).
public protocol MachineTranslator: Sendable {
    /// Language data installed: background fills run only then and never prompt for a download (§6.3).
    func isReady() async -> Bool
    /// One machine variant; nil or empty = "returned nothing".
    func translate(_ text: String) async throws -> String?
}
