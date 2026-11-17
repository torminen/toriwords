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
                        ],
                    ],
                ],
            ]),
            sources: ["ShareExtension/**"],
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
            sources: ["WidgetExtension/**"],
            dependencies: [
                .external(name: "ToriCore"),
                .external(name: "ToriShared"),
                .external(name: "ToriUI"),
            ]
        ),
    ]
)
