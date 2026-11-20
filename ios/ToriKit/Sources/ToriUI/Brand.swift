#if canImport(SwiftUI)
import SwiftUI

/// Logo F3-8, the app-icon mark (doc 35 §4): a "T" in the text colour whose bar spans an accent "W",
/// with a gap around the T stem cut out of the W so the background shows through.
/// Coordinates are fractions of the square frame; the stroke is 0.12 of the frame.
public struct LogoMark: View {
    public var size: CGFloat
    public var drawing: Drawing

    public init(size: CGFloat = 26, drawing: Drawing = .finished) {
        self.size = size
        self.drawing = drawing
    }

    /// How far each stroke is drawn, 0...1 (the launch animation draws the mark in); `.finished` is the static mark.
    public struct Drawing: Equatable, Sendable {
        public var w: CGFloat
        public var bar: CGFloat
        public var stem: CGFloat

        public init(w: CGFloat, bar: CGFloat, stem: CGFloat) {
            self.w = w
            self.bar = bar
            self.stem = stem
        }

        public static let finished = Drawing(w: 1, bar: 1, stem: 1)
    }

    public var body: some View {
        let s = size * 0.12
        ZStack {
            WShape().trim(from: 0, to: drawing.w)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: s, lineCap: .round, lineJoin: .round))
            // The gap shares the stem's path and trim, so while the stem draws down it cuts the W just ahead of its tip.
            StemShape().trim(from: 0, to: drawing.stem)
                .stroke(Color.black, style: StrokeStyle(lineWidth: s * 1.9, lineCap: .round))
                .blendMode(.destinationOut)
            StemShape().trim(from: 0, to: drawing.stem)
                .stroke(Palette.text, style: StrokeStyle(lineWidth: s, lineCap: .round))
            BarShape().fill(Palette.text)
                .scaleEffect(x: max(drawing.bar, 0.001), y: 1)
                .opacity(min(drawing.bar, 1))
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

    /// Vertical line at the centre, from just under the bar (0.15) down to the W's baseline (0.90).
    private struct StemShape: Shape {
        func path(in r: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.15))
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

/// Header layout E: 32 pt mark + 17 pt semibold "ToriWords", for the leading toolbar item (no large title).
/// The name is never truncated; text is capped at xxxLarge so it cannot crowd the trailing items.
public struct BrandHeader: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Spacing.s) {
            LogoMark(size: 32)
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
