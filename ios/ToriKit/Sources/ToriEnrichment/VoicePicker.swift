/// Pronunciation accent, per device (doc 36 §9).
public enum Accent: String, Sendable, CaseIterable {
    case us, uk
    public var language: String { self == .us ? "en-US" : "en-GB" }
}

/// Voice choice (doc 36 §9), kept free of AVFoundation so it is tested on Linux.
public enum VoicePicker {
    public enum Quality: Int, Comparable, Sendable {
        case `default` = 0, enhanced, premium
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Voice: Hashable, Sendable {
        public var identifier: String
        public var language: String
        public var quality: Quality
        public init(identifier: String, language: String, quality: Quality) {
            self.identifier = identifier
            self.language = language
            self.quality = quality
        }
    }

    /// Best voice of the accent's language (premium > enhanced > default), else any `en-*`; nil = no English voice.
    public static func pick(_ accent: Accent, among voices: [Voice]) -> Voice? {
        let best = { (vs: [Voice]) in vs.max { ($0.quality, $1.identifier) < ($1.quality, $0.identifier) } }
        return best(voices.filter { $0.language == accent.language })
            ?? best(voices.filter { $0.language.hasPrefix("en-") || $0.language == "en" })
    }
}
