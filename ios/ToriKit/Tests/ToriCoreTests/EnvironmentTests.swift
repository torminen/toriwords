import Foundation
import Testing
import ToriCore
import ToriTestSupport

@Test func fixtureLocatorFindsSharedFixtures() {
    #expect(FileManager.default.fileExists(atPath: FixtureLocator.url("README.md").path))
}

@Test func sha256MatchesKnownVector() {
    #expect(sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
