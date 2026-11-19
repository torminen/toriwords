import ProjectDescription

// Toriwords app + Share Extension + widget. Values come from Config/Shared.xcconfig; ToriKit tests run
// from the ToriKit package itself (README), so the project has no test targets.

let deploymentTargets = DeploymentTargets.iOS("18.0")
let settings = Settings.settings(
    base: ["SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete"],
    configurations: [
        .debug(name: .debug, xcconfig: "Config/Shared.xcconfig"),
        .release(name: .release, xcconfig: "Config/Shared.xcconfig"),
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
            bundleId: "com.toriwords.app",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "ToriWords",
                "CFBundleLocalizations": localizations,
                "UILaunchScreen": [:],
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
            ]),
            sources: ["App/**"],
            // The full dictionary when fetched (tools/dictionary/fetch.sh) and the committed sample; the app
            // installs the full file when present, else the sample (Debug/CI). Release fails without the full file.
            resources: ["App/**/*.xcstrings", "Resources/dictionary*.sqlite"],
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
            settings: .settings(base: ["ENABLE_USER_SCRIPT_SANDBOXING": "NO"])
        ),
        .target(
            name: "ToriwordsShare",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "com.toriwords.app.share",
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
            dependencies: [
                .external(name: "ToriCore"),
                .external(name: "ToriShared"),
                .external(name: "ToriDictionary"),
                .external(name: "ToriUI"),
            ]
        ),
        .target(
            name: "ToriwordsWidget",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "com.toriwords.app.widget",
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
            ]
        ),
    ]
)
