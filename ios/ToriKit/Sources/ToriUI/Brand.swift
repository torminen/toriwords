#if canImport(SwiftUI)
import SwiftUI

/// Logo B: a T-bar roof over a W.
public struct LogoMark: View {
    public var size: CGFloat

    public init(size: CGFloat = 26) { self.size = size }

    public var body: some View {
        ZStack {
            RoofShape().fill(Palette.text)
            WShape().stroke(Palette.text, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct RoofShape: Shape {
        func path(in r: CGRect) -> Path {
            Path(roundedRect: CGRect(x: r.minX + r.width * 0.04, y: r.minY + r.height * 0.06,
                                     width: r.width * 0.92, height: r.height * 0.13),
                 cornerRadius: r.height * 0.04)
        }
    }

    private struct WShape: Shape {
        func path(in r: CGRect) -> Path {
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
            var path = Path()
            path.addLines([p(0.12, 0.34), p(0.31, 0.9), p(0.5, 0.46), p(0.69, 0.9), p(0.88, 0.34)])
            return path
        }
    }
}

/// Header layout E: 26 pt mark + 17 pt semibold "ToriWords", for the leading toolbar item (no large title).
public struct BrandHeader: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Spacing.s) {
            LogoMark(size: 26)
            Text(verbatim: "ToriWords").font(Typography.heading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "ToriWords"))
        .accessibilityAddTraits(.isHeader)
    }
}

#if os(iOS)
#Preview("Header") {
    NavigationStack {
        Palette.background.ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandHeader() }
                ToolbarItem(placement: .topBarTrailing) { Button("Words") {} }
            }
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
#endif
