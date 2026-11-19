import Foundation
import ToriCore

/// `toriwords://` links: the widget and the reminder open Review; `add` opens Add with text.
public enum DeepLink: Hashable, Sendable {
    case review
    /// Text is untrusted (any app can open the link): trimmed, cut to `Capture.maxCharacters` code points, empty → nil.
    case add(text: String?)

    public static let scheme = "toriwords"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // `toriwords://review` has host "review"; also accept `toriwords:review`.
        let name = (parts.host ?? parts.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch name {
        case "review":
            self = .review
        case "add":
            let raw = parts.queryItems?.first { $0.name == "text" }?.value ?? ""
            let text = String(String.UnicodeScalarView(raw.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
                .prefix(Capture.maxCharacters)))
            self = .add(text: text.isEmpty ? nil : text)
        default:
            return nil
        }
    }

    public var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .review:
            c.host = "review"
        case .add(let text):
            c.host = "add"
            if let text { c.queryItems = [URLQueryItem(name: "text", value: text)] }
        }
        return c.url!
    }
}
