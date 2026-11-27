import Foundation

/// Finds the shared parity fixtures (`<repo>/fixtures`) without copying them:
/// env `TORI_FIXTURES` wins, otherwise the path is derived from this file's location in the repo.
public enum FixtureLocator {
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["TORI_FIXTURES"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // <repo>/ios/ToriKit/Tests/ToriTestSupport/FixtureLocator.swift → <repo>
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ToriTestSupport
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ToriKit
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()
        return repo.appendingPathComponent("fixtures", isDirectory: true)
    }

    public static func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }
}
