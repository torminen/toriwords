import Foundation

/// Build configuration read from Info.plist (values come from `Config/Shared.xcconfig`). No secrets.
enum AppConfig {
    static var backgroundRefreshTaskID: String {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.first
            ?? "com.toriwords.app.refresh"
    }

    static var appVersion: String { string("CFBundleShortVersionString") ?? "0" }

    private static func string(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
