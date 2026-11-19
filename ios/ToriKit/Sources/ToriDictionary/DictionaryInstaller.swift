import Foundation
import GRDB
import ToriCore

/// Copies the bundled `dictionary.sqlite` into the App Group when its `meta.dictionary_version` differs from the
/// installed one: copy to `<installed>.tmp`, verify size and SHA-256, exclude from backup, atomic rename.
/// On any failure the old file stays in place.
public struct DictionaryInstaller: Sendable {
    public enum Outcome: Equatable, Sendable {
        case unchanged(version: String)
        case installed(version: String, previous: String?)

        /// The app then calls `EnrichmentOrchestrator.updateDictionary` (re-runs enrichment on `unavailable` Entries).
        public var versionChanged: Bool { if case .installed = self { true } else { false } }
    }

    public enum Failure: Error, Equatable {
        case verificationFailed(expected: String, actual: String)
        case renameFailed(errno: Int32)
    }

    public let bundled: URL
    public let installed: URL
    /// Injectable for tests (e.g. a corrupting copy); default `FileManager.copyItem`.
    let copy: @Sendable (URL, URL) throws -> Void

    public init(bundled: URL, installed: URL,
                copy: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }) {
        self.bundled = bundled
        self.installed = installed
        self.copy = copy
    }

    public func installIfNeeded() throws -> Outcome {
        let version = try BundledDictionary(path: bundled.path).version
        let previous = FileManager.default.fileExists(atPath: installed.path)
            ? (try? BundledDictionary(path: installed.path))?.version : nil
        if previous == version { return .unchanged(version: version) }

        let tmp = installed.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tmp)
        do {
            try copy(bundled, tmp)
            let expected = try sha256Hex(contentsOf: bundled)
            let actual = try sha256Hex(contentsOf: tmp)
            guard try size(tmp) == size(bundled), actual == expected else {
                throw Failure.verificationFailed(expected: expected, actual: actual)
            }
            #if canImport(Darwin)
            var tmpURL = tmp
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try tmpURL.setResourceValues(values)
            #endif
            guard rename(tmp.path, installed.path) == 0 else { throw Failure.renameFailed(errno: errno) }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
        return .installed(version: version, previous: previous)
    }

    private func size(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? -1
    }
}
