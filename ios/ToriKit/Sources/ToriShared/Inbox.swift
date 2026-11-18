import Foundation
import ToriCore

/// One pending capture written by the Share Extension, format 1 (doc 36 §5.3.1).
public struct InboxFile: Codable, Hashable, Sendable {
    public struct LanguagePair: Codable, Hashable, Sendable {
        public var native: String
        public var target: String
        public init(native: String, target: String) {
            self.native = native
            self.target = target
        }
    }

    public struct Source: Codable, Hashable, Sendable {
        public var url: String?
        public var title: String?
        /// "Safari" only when the Safari preprocessing result was present (§4 `source.app`, CH-23); else absent.
        public var app: String?
        public init(url: String? = nil, title: String? = nil, app: String? = nil) {
            self.url = url
            self.title = title
            self.app = app
        }
    }

    public struct Provenance: Codable, Hashable, Sendable {
        /// `wiktionary` or `user`.
        public var kind: String
        public var dictVersion: String?
        public var headwordKey: String?
        public var senseOrdinal: Int?
        public init(kind: String, dictVersion: String? = nil, headwordKey: String? = nil, senseOrdinal: Int? = nil) {
            self.kind = kind
            self.dictVersion = dictVersion
            self.headwordKey = headwordKey
            self.senseOrdinal = senseOrdinal
        }
    }

    public struct ChosenSense: Codable, Hashable, Sendable {
        public var translation: String?
        public var definition: String?
        public var pos: String?
        public var provenance: Provenance
        public init(translation: String?, definition: String? = nil, pos: String? = nil, provenance: Provenance) {
            self.translation = translation
            self.definition = definition
            self.pos = pos
            self.provenance = provenance
        }
    }

    public static let currentFormat = 1

    public var format: Int
    public var captureId: ToriID
    public var capturedAt: Int64
    public var utcOffsetMin: Int
    public var languagePair: LanguagePair
    public var term: String
    public var sentence: String?
    public var highlight: Capture.Highlight?
    public var source: Source?
    public var tags: [String]?
    public var chosenSenses: [ChosenSense]
    public var typedTranslation: String?
    public var origin: String
    /// The user tapped Resume learning in the sheet.
    public var resume: Bool

    public init(captureId: ToriID, capturedAt: Int64, utcOffsetMin: Int, languagePair: LanguagePair = .init(native: "ru", target: "en"),
                term: String, sentence: String? = nil, highlight: Capture.Highlight? = nil, source: Source? = nil,
                tags: [String]? = nil, chosenSenses: [ChosenSense] = [], typedTranslation: String? = nil,
                origin: String = "shared", resume: Bool = false) {
        self.format = Self.currentFormat
        self.captureId = captureId
        self.capturedAt = capturedAt
        self.utcOffsetMin = utcOffsetMin
        self.languagePair = languagePair
        self.term = term
        self.sentence = sentence
        self.highlight = highlight
        self.source = source
        self.tags = tags
        self.chosenSenses = chosenSenses
        self.typedTranslation = typedTranslation
        self.origin = origin
        self.resume = resume
    }

    enum CodingKeys: String, CodingKey {
        case format, captureId, capturedAt, utcOffsetMin, languagePair, term, sentence, highlight, source, tags,
             chosenSenses, typedTranslation, origin, resume
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        captureId = try c.decode(ToriID.self, forKey: .captureId)
        capturedAt = try c.decode(Int64.self, forKey: .capturedAt)
        utcOffsetMin = try c.decode(Int.self, forKey: .utcOffsetMin)
        languagePair = try c.decode(LanguagePair.self, forKey: .languagePair)
        term = try c.decode(String.self, forKey: .term)
        sentence = try c.decodeIfPresent(String.self, forKey: .sentence)
        highlight = try c.decodeIfPresent(Capture.Highlight.self, forKey: .highlight)
        source = try c.decodeIfPresent(Source.self, forKey: .source)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        chosenSenses = try c.decodeIfPresent([ChosenSense].self, forKey: .chosenSenses) ?? []
        typedTranslation = try c.decodeIfPresent(String.self, forKey: .typedTranslation)
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? "shared"
        resume = try c.decodeIfPresent(Bool.self, forKey: .resume) ?? false
    }
}

/// The `inbox/` directory: one `<captureId>.json` per pending capture.
public struct Inbox: Sendable {
    public let directory: URL

    public enum Item: Sendable {
        case capture(InboxFile)
        /// Unknown `format`: leave the file untouched.
        case unknownFormat(Int)
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for captureId: ToriID) -> URL { directory.appendingPathComponent("\(captureId).json") }

    /// Pending capture IDs in UUIDv7 byte order; temp files and other names are ignored.
    public func pending() -> [ToriID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            name.hasSuffix(".json") ? ToriID(String(name.dropLast(5))) : nil
        }.sorted()
    }

    public func read(_ captureId: ToriID) throws -> Item {
        let data = try Data(contentsOf: url(for: captureId))
        struct Header: Decodable { var format: Int }
        let format = try JSONDecoder().decode(Header.self, from: data).format
        guard format == InboxFile.currentFormat else { return .unknownFormat(format) }
        return .capture(try JSONDecoder().decode(InboxFile.self, from: data))
    }

    /// Share Extension side: atomic write (`inbox/.tmp-<id>.json` → `inbox/<id>.json`).
    public func write(_ file: InboxFile) throws {
        try AtomicFile.write(file, to: url(for: file.captureId))
    }

    public func delete(_ captureId: ToriID) throws {
        do {
            try FileManager.default.removeItem(at: url(for: captureId))
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        }
    }
}
