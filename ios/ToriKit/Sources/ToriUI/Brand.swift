#if canImport(SwiftUI)
import SwiftUI

/// Logo F3-8, the app-icon mark (doc 35 §4): a "T" in the text colour whose bar spans an accent "W",
/// with a gap around the T stem cut out of the W so the background shows through.
/// Coordinates are fractions of the square frame; the stroke is 0.12 of the frame.
public struct LogoMark: View {
    public var size: CGFloat

    public init(size: CGFloat = 26) { self.size = size }

    public var body: some View {
        let s = size * 0.12
        ZStack {
            WShape().stroke(Palette.accent, style: StrokeStyle(lineWidth: s, lineCap: .round, lineJoin: .round))
            StemShape(top: 0.20).stroke(Color.black, style: StrokeStyle(lineWidth: s * 1.9, lineCap: .round))
                .blendMode(.destinationOut)
            StemShape(top: 0.15).stroke(Palette.text, style: StrokeStyle(lineWidth: s, lineCap: .round))
            BarShape().fill(Palette.text)
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct WShape: Shape {
        func path(in r: CGRect) -> Path {
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
            var path = Path()
            path.addLines([p(0.17, 0.30), p(0.31, 0.90), p(0.50, 0.30), p(0.69, 0.90), p(0.83, 0.30)])
            return path
        }
    }

    /// Vertical line at the centre, from `top` down to the W's baseline (0.90).
    private struct StemShape: Shape {
        var top: CGFloat
        func path(in r: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: r.midX, y: r.minY + r.height * top))
            path.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.90))
            return path
        }
    }

    private struct BarShape: Shape {
        func path(in r: CGRect) -> Path {
            Path(roundedRect: CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.06,
                                     width: r.width * 0.76, height: r.height * 0.12),
                 cornerRadius: r.height * 0.12 * 0.3)
        }
    }
}

/// Header layout E: 26 pt mark + 17 pt semibold "ToriWords", for the leading toolbar item (no large title).
/// The name is never truncated; text is capped at xxxLarge so it cannot crowd the trailing items.
public struct BrandHeader: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Spacing.s) {
            LogoMark(size: 26)
            Text(verbatim: "ToriWords").font(Typography.heading)
        }
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "ToriWords"))
        .accessibilityAddTraits(.isHeader)
    }
}

#if os(iOS)
public extension ToolbarContent {
    /// Drops the shared Liquid Glass background iOS 26+ draws behind toolbar items; no-op before iOS 26.
    @ToolbarContentBuilder
    func hidingSharedBackground() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

#Preview("Header") {
    NavigationStack {
        Palette.background.ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandHeader() }.hidingSharedBackground()
                ToolbarItem(placement: .topBarTrailing) { Button("Words") {} }
            }
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
#endif
