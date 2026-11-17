import Foundation
import ToriDictionary
import ToriEnrichment
import ToriShared

/// §8.3: installs the bundled `dictionary.sqlite` into the App Group (copy + verify + rename off the main actor)
/// and opens it read-only. A version change is reported so enrichment re-runs `unavailable` Entries.
@MainActor final class AppDictionaryInstaller: DictionaryInstalling {
    private(set) var dictionary: BundledDictionary?
    private(set) var versionChanged = false

    func installIfNeeded(into group: AppGroup?) async throws -> (any DictionaryLookup)? {
        guard let group, let bundled = Bundle.main.url(forResource: "dictionary", withExtension: "sqlite")
            ?? Bundle.main.url(forResource: "dictionary-sample", withExtension: "sqlite") else { return nil }
        let installed = group.dictionary
        let (dictionary, changed) = try await Task.detached {
            let outcome = try DictionaryInstaller(bundled: bundled, installed: installed).installIfNeeded()
            return (try BundledDictionary(path: installed.path), outcome.versionChanged)
        }.value
        self.dictionary = dictionary
        versionChanged = changed
        return dictionary
    }
}
