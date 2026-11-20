// swift-tools-version: 6.2
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

// Static frameworks: one copy of each module per binary (app, share, widget), no duplicate dynamic frameworks.
let packageSettings = PackageSettings(
    productTypes: [
        "ToriCore": .staticFramework,
        "ToriShared": .staticFramework,
        "ToriDictionary": .staticFramework,
        "ToriStore": .staticFramework,
        "ToriSync": .staticFramework,
        "ToriEnrichment": .staticFramework,
        "ToriUI": .staticFramework,
        "GRDB": .staticFramework,
    ],
    // Packages need every configuration the project has (Project.swift adds Personal).
    baseSettings: .settings(configurations: [
        .debug(name: .debug), .release(name: .release), .debug(name: "Personal"),
    ])
)
#endif

// ToriKit is the only package the project sees; GRDB comes in transitively.
let package = Package(
    name: "ToriwordsDependencies",
    dependencies: [.package(path: "../ToriKit")]
)
