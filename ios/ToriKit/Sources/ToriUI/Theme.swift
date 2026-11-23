#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Theme tokens. Light values are the wireframe tokens; dark values are the iOS system dark equivalents
/// (UQ-5 is open: no dark palette is drawn, the assignment asks for system semantics).
public enum Palette {
    public static let accent = Color.dynamic(light: 0x12875A, dark: 0x2FBF7F)
    public static let background = Color.dynamic(light: 0xF2F2F7, dark: 0x000000)
    public static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let text = Color.dynamic(light: 0x000000, dark: 0xFFFFFF)
    public static let textSecondary = Color.dynamic(light: 0x6C6C70, dark: 0x98989F)
    public static let border = Color.dynamic(light: 0xC6C6C8, dark: 0x38383A)
    /// Delete, Forgot, destructive rows.
    public static let danger = Color.dynamic(light: 0xFF3B30, dark: 0xFF453A)
    /// Remembered, "Known" swipe.
    public static let success = Color.dynamic(light: 0x34C759, dark: 0x30D158)
    public static let dim = Color.black.opacity(0.4)
    public static let tip = Color.dynamic(light: 0xFFF4D6, dark: 0x3A3220)

    /// Badge and banner fills.
    public static let infoFill = Color.dynamic(light: 0xD5EEE2, dark: 0x0C3324)
    public static let successFill = Color.dynamic(light: 0xD8F5DF, dark: 0x0F3A1C)
    public static let warningFill = Color.dynamic(light: 0xFFF0D1, dark: 0x3D2E0A)
    public static let neutralFill = Color.dynamic(light: 0xE5E5EA, dark: 0x2C2C2E)
}

/// Text styles follow Dynamic Type; sizes in comments are the UI spec's approximations at the default size.
public enum Typography {
    /// Card word, 28–32 bold.
    public static let cardWord = Font.title.weight(.bold)
    /// Recall front translation(s).
    public static let cardTranslation = Font.title2.weight(.semibold)
    /// Section headings, 17 semibold.
    public static let heading = Font.headline
    /// Body, ~16.
    public static let body = Font.body
    /// Secondary, ~14.
    public static let secondary = Font.subheadline
    /// Group labels, 12 uppercase (apply `.textCase(.uppercase)`).
    public static let groupLabel = Font.caption
}

public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 32
}

public enum Radius {
    public static let chip: CGFloat = 8
    public static let button: CGFloat = 12
    public static let cell: CGFloat = 12
    public static let card: CGFloat = 16
    public static let alert: CGFloat = 14
}

extension Color {
    /// A colour that follows the light/dark appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
        #else
        Color(rgb: light)
        #endif
    }

    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif
#endif
