import Foundation
import Testing
@testable import ToriDictionary

struct InstallerHarness {
    let dir: URL
    let bundled: URL
    let installed: URL

    init() throws {
        dir = try tempDir()
        bundled = resource("dictionary-sample.sqlite")
        installed = dir.appendingPathComponent("dictionary.sqlite")
    }

    func version() throws -> String { try BundledDictionary(path: installed.path).version }
    var tmpExists: Bool { FileManager.default.fileExists(atPath: installed.path + ".tmp") }
}

@Test func freshInstallThenSameVersionIsSkipped() throws {
    let h = try InstallerHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let installer = DictionaryInstaller(bundled: h.bundled, installed: h.installed)
    let first = try installer.installIfNeeded()
    #expect(first == .installed(version: sample.version, previous: nil) && first.versionChanged)
    #expect(try h.version() == sample.version && !h.tmpExists)
    let second = try installer.installIfNeeded()
    #expect(second == .unchanged(version: sample.version) && !second.versionChanged)
}

@Test func versionChangeReplacesTheInstalledFile() throws {
    let h = try InstallerHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    try makeDictionary(at: h.installed, version: "2026.10.1")
    let outcome = try DictionaryInstaller(bundled: h.bundled, installed: h.installed).installIfNeeded()
    #expect(outcome == .installed(version: sample.version, previous: "2026.10.1"))
    #expect(try h.version() == sample.version)
}

@Test func unreadableInstalledFileIsReplaced() throws {
    let h = try InstallerHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    try Data("garbage".utf8).write(to: h.installed)
    #expect(try DictionaryInstaller(bundled: h.bundled, installed: h.installed).installIfNeeded().versionChanged)
    #expect(try h.version() == sample.version)
}

@Test func hashMismatchKeepsTheOldFile() throws {
    let h = try InstallerHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    try makeDictionary(at: h.installed, version: "2026.10.1")
    let corrupting = DictionaryInstaller(bundled: h.bundled, installed: h.installed) { from, to in
        var data = try Data(contentsOf: from)
        data[data.count / 2] ^= 0xFF
        try data.write(to: to)
    }
    #expect(throws: DictionaryInstaller.Failure.self) { try corrupting.installIfNeeded() }
    #expect(try h.version() == "2026.10.1" && !h.tmpExists)
}
