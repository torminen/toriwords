import ProjectDescription

// Toriwords app + Share Extension + widget. Values come from Config/Shared.xcconfig; ToriKit tests run
// from the ToriKit package itself (README), so the project has no test targets.

let deploymentTargets = DeploymentTargets.iOS("18.0")
let personal: ConfigurationName = "Personal"
/// A Personal Team cannot sign iCloud or App Groups, so the Personal configuration signs without entitlements.
let noEntitlementsInPersonal: [Configuration] = [.debug(name: personal, settings: ["CODE_SIGN_ENTITLEMENTS": ""])]
let settings = Settings.settings(
    base: [
        "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
        // Off, against Xcode 27's recommendation: keys like "Add a word" / "Add a word…" map to one symbol and fail
        // the build, and the app uses Text("…") literals, not generated symbols.
        "STRING_CATALOG_GENERATE_SYMBOLS": "NO",
        // Off: the string catalogs are edited by hand (all keys "manual"). Xcode 27's extraction rewrote them on every
        // build and added untranslated "%@" duplicates of the "%lld" keys the app actually looks up.
        "SWIFT_EMIT_LOC_STRINGS": "NO",
    ],
    configurations: [
        .debug(name: .debug, xcconfig: "Config/Shared.xcconfig"),
        .release(name: .release, xcconfig: "Config/Shared.xcconfig"),
        // Free Apple ID (Personal Team) device builds: see Config/Personal.xcconfig and the README.
        .debug(name: personal, xcconfig: "Config/Personal.xcconfig"),
    ]
)

/// App Group shared by the app, the Share Extension and the widget.
let appGroup: Plist.Value = .array([.string("$(TORI_APP_GROUP_ID)")])
let extensionEntitlements: Entitlements = .dictionary(["com.apple.security.application-groups": appGroup])
/// The app also syncs through the iCloud private database (CloudKit container below).
let appEntitlements: Entitlements = .dictionary([
    "com.apple.security.application-groups": appGroup,
    "com.apple.developer.icloud-services": .array([.string("CloudKit")]),
    "com.apple.developer.icloud-container-identifiers": .array([.string("iCloud.com.toriwords.app")]),
])

/// UI in English and Russian, on every target.
let localizations: Plist.Value = .array([.string("en"), .string("ru")])

let project = Project(
    name: "Toriwords",
    settings: settings,
    targets: [
        .target(
            name: "Toriwords",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "$(TORI_BUNDLE_ID)",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "ToriWords",
                "CFBundleLocalizations": localizations,
                // Background only: LaunchView draws the mark in from this frame. The colour mirrors Palette.background.
                "UILaunchScreen": ["UIColorName": "LaunchBackground"],
                // Phone-first portrait layouts; iPad runs the same adaptive layouts in every orientation.
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
                ],
                "ITSAppUsesNonExemptEncryption": false,
                // toriwords:// deep links.
                "CFBundleURLTypes": [
                    ["CFBundleURLName": "com.toriwords.app", "CFBundleURLSchemes": ["$(TORI_URL_SCHEME)"]],
                ],
                "BGTaskSchedulerPermittedIdentifiers": ["$(TORI_BG_REFRESH_TASK_ID)"],
                "UIBackgroundModes": ["fetch"],
                // NO in the Personal configuration: no CloudKit entitlement, so no sync (AppConfig.cloudSyncEnabled).
                "ToriCloudSync": "$(TORI_CLOUD_SYNC)",
            ]),
            sources: ["App/**"],
            // The full dictionary when fetched (tools/dictionary/fetch.sh) and the committed sample; the app
            // installs the full file when present, else the sample (Debug/CI). Release fails without the full file.
            // Assets.xcassets holds the app icon.
            resources: ["App/**/*.xcstrings", "Resources/dictionary*.sqlite", "Resources/Assets.xcassets"],
            entitlements: appEntitlements,
            scripts: [
                .pre(script: """
                    if [ "$CONFIGURATION" = "Release" ] && [ ! -f "$SRCROOT/Resources/dictionary.sqlite" ]; then
                      echo "error: Resources/dictionary.sqlite missing; run tools/dictionary/fetch.sh"; exit 1
                    fi
                    """, name: "Require full dictionary in Release", basedOnDependencyAnalysis: false),
            ],
            dependencies: [
                .target(name: "ToriwordsShare"),
                .target(name: "ToriwordsWidget"),
                .external(name: "ToriCore"),
                .external(name: "ToriShared"),
                .external(name: "ToriDictionary"),
                .external(name: "ToriStore"),
                .external(name: "ToriSync"),
                .external(name: "ToriEnrichment"),
                .external(name: "ToriUI"),
            ],
            // The Release dictionary check reads Resources/ outside declared inputs (a declared input would fail Debug
            // builds without the full file), so this target's scripts run unsandboxed.
            settings: .settings(base: [
                "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                // No AccentColor asset: the UI tints with Palette.accent.
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
            ], configurations: noEntitlementsInPersonal)
        ),
        .target(
            name: "ToriwordsShare",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "$(TORI_BUNDLE_ID).share",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "ToriWords",
                "CFBundleLocalizations": localizations,
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "NSExtensionAttributes": [
                        "NSExtensionActivationRule": [
                            "NSExtensionActivationSupportsText": true,
                            "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                            // Safari runs ExtensionPreprocessing.js for web pages.
                            "NSExtensionActivationSupportsWebPageWithMaxCount": 1,
                        ],
                        "NSExtensionJavaScriptPreprocessingFile": "ExtensionPreprocessing",
                    ],
                ],
            ]),
            sources: ["ShareExtension/**/*.swift"],
            resources: ["ShareExtension/ExtensionPreprocessing.js", "ShareExtension/*.xcstrings"],
            entitlements: extensionEntitlements,
            scripts: [
                // Personal builds have no App Group, so the extension could not hand words to the app. Xcode validates
                // every embedded extension, so it cannot be left out per configuration; in Personal it never activates
                // instead (Share does not list ToriWords): INFOPLIST_FILE points at this copy with FALSEPREDICATE.
                .pre(script: """
                    cp "$SCRIPT_INPUT_FILE_0" "$SCRIPT_OUTPUT_FILE_0"
                    /usr/libexec/PlistBuddy -c "Delete :NSExtension:NSExtensionAttributes:NSExtensionActivationRule" \\
                      -c "Add :NSExtension:NSExtensionAttributes:NSExtensionActivationRule string FALSEPREDICATE" \\
                      "$SCRIPT_OUTPUT_FILE_0"
                    """, name: "Personal Info.plist (never activate)",
                    inputPaths: ["$(SRCROOT)/Derived/InfoPlists/ToriwordsShare-Info.plist"],
                    outputPaths: ["$(DERIVED_FILE_DIR)/ToriwordsShare-Personal-Info.plist"]),
            ],
            dependencies: [
                .external(name: "ToriCore"),
                .external(name: "ToriShared"),
                .external(name: "ToriDictionary"),
                .external(name: "ToriUI"),
            ],
            settings: .settings(configurations: [.debug(name: personal, settings: [
                "CODE_SIGN_ENTITLEMENTS": "",
                "INFOPLIST_FILE": "$(DERIVED_FILE_DIR)/ToriwordsShare-Personal-Info.plist",
            ])])
        ),
        .target(
            name: "ToriwordsWidget",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "$(TORI_BUNDLE_ID).widget",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "ToriWords",
                "CFBundleLocalizations": localizations,
                "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
            ]),
            sources: ["WidgetExtension/**/*.swift"],
            resources: ["WidgetExtension/*.xcstrings"],
            entitlements: extensionEntitlements,
            dependencies: [
                .external(name: "ToriCore"),
                .external(name: "ToriShared"),
                .external(name: "ToriUI"),
            ],
            settings: .settings(configurations: noEntitlementsInPersonal)
        ),
    ],
    schemes: [
        // Toriwords (autogenerated) is the full build; this one runs and archives the Personal configuration.
        .scheme(
            name: "Toriwords-Personal",
            buildAction: .buildAction(targets: ["Toriwords"]),
            runAction: .runAction(configuration: personal),
            archiveAction: .archiveAction(configuration: personal),
            profileAction: .profileAction(configuration: personal),
            analyzeAction: .analyzeAction(configuration: personal)
        ),
    ]
)
