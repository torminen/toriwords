import ProjectDescription

// Skeleton (plan step 1). Entitlements, full Info.plist, dictionary build phase and test targets: step 11.

let deploymentTargets = DeploymentTargets.iOS("26.0")
let settings = Settings.settings(
    base: ["SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete"],
    configurations: [
        .debug(name: .debug, xcconfig: "Config/Shared.xcconfig"),
        .release(name: .release, xcconfig: "Config/Shared.xcconfig"),
    ]
)

/// App Group shared by the app, the Share Extension and the widget (doc 36 §2.2).
let appGroupEntitlements: Entitlements = .dictionary([
    "com.apple.security.application-groups": .array([.string("$(TORI_APP_GROUP_ID)")]),
])

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
                "UILaunchScreen": [:],
                "CFBundleURLTypes": [["CFBundleURLSchemes": ["$(TORI_URL_SCHEME)"]]],
                "BGTaskSchedulerPermittedIdentifiers": ["$(TORI_BG_REFRESH_TASK_ID)"],
                "UIBackgroundModes": ["fetch"],
            ]),
            sources: ["App/**"],
            // §8.3: the full dictionary when fetched (tools/dictionary/fetch.sh) and the committed sample; the app
            // installs the full file when present, else the sample (Debug/CI). Release fails without the full file.
            resources: ["App/**/*.xcstrings", "Resources/dictionary*.sqlite"],
            entitlements: appGroupEntitlements,
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
            ]
        ),
        .target(
            name: "ToriwordsShare",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "com.toriwords.app.share",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "ToriWords",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "NSExtensionAttributes": [
                        "NSExtensionActivationRule": [
                            "NSExtensionActivationSupportsText": true,
                            "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                            // Safari runs ExtensionPreprocessing.js for web pages (§5.1, P1).
                            "NSExtensionActivationSupportsWebPageWithMaxCount": 1,
                        ],
                        "NSExtensionJavaScriptPreprocessingFile": "ExtensionPreprocessing",
                    ],
                ],
            ]),
            sources: ["ShareExtension/**/*.swift"],
            resources: ["ShareExtension/ExtensionPreprocessing.js", "ShareExtension/*.xcstrings"],
            entitlements: appGroupEntitlements,
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
                "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
            ]),
            sources: ["WidgetExtension/**/*.swift"],
            resources: ["WidgetExtension/*.xcstrings"],
            entitlements: appGroupEntitlements,
            dependencies: [
                .external(name: "ToriCore"),
                .external(name: "ToriShared"),
                .external(name: "ToriUI"),
            ]
        ),
    ]
)
