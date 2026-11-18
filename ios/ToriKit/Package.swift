// swift-tools-version: 6.2
import PackageDescription

// Module graph: doc 36 §2.3. Arrows are allowed dependencies; nothing else.
let grdb = Target.Dependency.product(name: "GRDB", package: "GRDB.swift")
// CryptoKit on Apple platforms; swift-crypto only so the package builds and tests on Linux.
let crypto = Target.Dependency.product(
    name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))

let package = Package(
    name: "ToriKit",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "ToriCore", targets: ["ToriCore"]),
        .library(name: "ToriShared", targets: ["ToriShared"]),
        .library(name: "ToriDictionary", targets: ["ToriDictionary"]),
        .library(name: "ToriStore", targets: ["ToriStore"]),
        .library(name: "ToriSync", targets: ["ToriSync"]),
        .library(name: "ToriEnrichment", targets: ["ToriEnrichment"]),
        .library(name: "ToriUI", targets: ["ToriUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "4.5.0"),
    ],
    targets: [
        .target(name: "ToriCore", dependencies: [crypto]),
        .target(name: "ToriShared", dependencies: ["ToriCore"]),
        .target(name: "ToriDictionary", dependencies: ["ToriCore", grdb]),
        .target(name: "ToriStore", dependencies: ["ToriCore", "ToriShared", grdb]),
        .target(name: "ToriSync", dependencies: ["ToriCore", "ToriStore"]),
        .target(name: "ToriEnrichment", dependencies: ["ToriCore", "ToriDictionary", "ToriStore"]),
        .target(name: "ToriUI", dependencies: ["ToriCore"]),

        .target(name: "ToriTestSupport", path: "Tests/ToriTestSupport"),
        .testTarget(name: "ToriCoreTests", dependencies: ["ToriCore", "ToriTestSupport"]),
        .testTarget(name: "ToriSharedTests", dependencies: ["ToriShared", "ToriTestSupport"]),
        .testTarget(name: "ToriDictionaryTests", dependencies: ["ToriDictionary", "ToriTestSupport", grdb]),
        .testTarget(name: "ToriStoreTests", dependencies: ["ToriStore", "ToriTestSupport", grdb]),
        .testTarget(name: "ToriSyncTests", dependencies: ["ToriSync", "ToriStore", "ToriTestSupport", grdb]),
        .testTarget(name: "ToriEnrichmentTests", dependencies: ["ToriEnrichment", "ToriDictionary", "ToriTestSupport"]),
        .testTarget(name: "ToriUITests", dependencies: ["ToriUI", "ToriCore"]),
    ],
    swiftLanguageModes: [.v6]
)
