import Foundation
import ToriCore

/// `vocab-index.json`: duplicate hints for the Share Extension.
public struct VocabIndex: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case active, known, paused }

    /// Encoded as `[matchKey, canonicalEntryId, translations, status]`.
    public struct Entry: Codable, Hashable, Sendable {
        public var matchKey: String
        public var entryId: ToriID
        public var translations: [String]
        public var status: Status

        public init(matchKey: String, entryId: ToriID, translations: [String], status: Status) {
            self.matchKey = matchKey
            self.entryId = entryId
            self.translations = translations
            self.status = status
        }

        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            matchKey = try c.decode(String.self)
            entryId = try c.decode(ToriID.self)
            translations = try c.decode([String].self)
            status = try c.decode(Status.self)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(matchKey)
            try c.encode(entryId)
            try c.encode(translations)
            try c.encode(status)
        }
    }

    /// Encoded as `[tagKey, displayName]`.
    public struct Tag: Codable, Hashable, Sendable {
        public var key: String
        public var name: String

        public init(key: String, name: String) {
            self.key = key
            self.name = name
        }

        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            key = try c.decode(String.self)
            name = try c.decode(String.self)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(key)
            try c.encode(name)
        }
    }

    public var format: Int
    public var generatedAt: Int64
    public var entries: [Entry]
    public var tags: [Tag]

    public init(generatedAt: Int64, entries: [Entry], tags: [Tag]) {
        self.format = 1
        self.generatedAt = generatedAt
        self.entries = entries
        self.tags = tags
    }

    /// The hint for a term: the entry whose match key equals the term's.
    public func entry(matching term: String) -> Entry? {
        let key = TextKey.matchKey(term)
        return entries.first { Array($0.matchKey.utf8) == Array(key.utf8) }
    }
}

/// `capture-sticky.json`: written and read by the Share Extension only.
public struct CaptureSticky: Codable, Hashable, Sendable {
    public static let offerWindowMs: Int64 = 30 * 60 * 1000

    public var format: Int
    public var updatedAt: Int64
    public var sourceTitle: String?
    public var tags: [String]
    public var tipShown: Bool

    public init(updatedAt: Int64, sourceTitle: String?, tags: [String], tipShown: Bool) {
        self.format = 1
        self.updatedAt = updatedAt
        self.sourceTitle = sourceTitle
        self.tags = tags
        self.tipShown = tipShown
    }

    /// Source title and tags are offered for 30 minutes after `updatedAt`; `tipShown` never expires.
    public func offered(now: Int64) -> (sourceTitle: String?, tags: [String]) {
        now - updatedAt <= Self.offerWindowMs ? (sourceTitle, tags) : (nil, [])
    }
}

extension AppGroup {
    public func writeWidgetSnapshot(_ snapshot: WidgetSnapshot) throws { try AtomicFile.write(snapshot, to: widgetSnapshot) }
    public func readWidgetSnapshot() throws -> WidgetSnapshot? { try AtomicFile.read(WidgetSnapshot.self, from: widgetSnapshot) }
    public func writeVocabIndex(_ index: VocabIndex) throws { try AtomicFile.write(index, to: vocabIndex) }
    public func readVocabIndex() throws -> VocabIndex? { try AtomicFile.read(VocabIndex.self, from: vocabIndex) }
    public func writeCaptureSticky(_ sticky: CaptureSticky) throws { try AtomicFile.write(sticky, to: captureSticky) }
    public func readCaptureSticky() throws -> CaptureSticky? { try AtomicFile.read(CaptureSticky.self, from: captureSticky) }
}
