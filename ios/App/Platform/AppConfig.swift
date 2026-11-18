import Foundation
import ToriSync

/// Build configuration read from Info.plist (values come from `Config/Shared.xcconfig`). No secrets.
enum AppConfig {
    /// nil while `TORI_API_BASE_URL` is empty: sync stays off and the app is local-only.
    static var apiBaseURL: URL? {
        string("ToriAPIBaseURL").flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    static var backgroundRefreshTaskID: String {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.first
            ?? "com.toriwords.app.refresh"
    }

    /// nil while the client ID is the `REPLACE_ME` placeholder.
    static var google: GoogleOAuthConfig? {
        guard let id = string("ToriGoogleClientID"), let scheme = string("ToriGoogleReversedClientID"),
              !id.contains("REPLACE_ME") else { return nil }
        return GoogleOAuthConfig(clientID: id, redirectScheme: scheme)
    }

    static var appVersion: String { string("CFBundleShortVersionString") ?? "0" }

    private static func string(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
