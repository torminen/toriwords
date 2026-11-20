import Foundation
import ToriDictionary
import ToriEnrichment
import ToriShared

/// Opens the bundled `dictionary.sqlite` read-only in place (the Share Extension reads the same file) and reports a
/// version change since the last launch, so enrichment re-runs `unavailable` Entries.
@MainActor final class AppDictionaryLoader: DictionaryLoading {
    private(set) var dictionary: BundledDictionary?
    private(set) var versionChanged = false
    private let defaults: UserDefaults
    private static let versionKey = "dictionaryVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(appGroup: AppGroup?) async throws -> (any DictionaryLookup)? {
        guard let url = BundledDictionary.bundledURL() else { return nil }
        let dictionary = try await Task.detached {
            // Earlier builds copied the dictionary (~58 MB) into the App Group; free that space.
            if let appGroup {
                for legacy in [appGroup.root.appendingPathComponent("dictionary.sqlite"),
                               appGroup.root.appendingPathComponent("dictionary.sqlite.tmp")] {
                    try? FileManager.default.removeItem(at: legacy)
                }
            }
            return try BundledDictionary(path: url.path)
        }.value
        self.dictionary = dictionary
        versionChanged = defaults.string(forKey: Self.versionKey) != dictionary.version
        defaults.set(dictionary.version, forKey: Self.versionKey)
        return dictionary
    }
}
