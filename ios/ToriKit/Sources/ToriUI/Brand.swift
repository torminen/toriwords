#if canImport(SwiftUI)
import SwiftUI

/// Logo F3-8, the app-icon mark (doc 35 §4): a "T" in the text colour drawn as a tree over an accent "W" (the grass).
/// The bar is a gently waved branch with an accent leaf at its right end; a gap around the T stem is cut out of the W
/// so the background shows through. Coordinates are fractions of the square frame; the stroke is 0.12 of the frame.
/// The app icon (`AppIcon.png`, `AppIcon-dark.png`) is this mark at 75 % of the icon side.
public struct LogoMark: View {
    public var size: CGFloat
    public var drawing: Drawing

    public init(size: CGFloat = 26, drawing: Drawing = .finished) {
        self.size = size
        self.drawing = drawing
    }

    /// How far each part is drawn, 0...1 (the launch animation grows the mark in); `.finished` is the static mark.
    /// `leaf` unfolds the leaf from its base rather than drawing a stroke.
    public struct Drawing: Equatable, Sendable {
        public var w: CGFloat
        public var bar: CGFloat
        public var stem: CGFloat
        public var leaf: CGFloat

        public init(w: CGFloat, bar: CGFloat, stem: CGFloat, leaf: CGFloat) {
            self.w = w
            self.bar = bar
            self.stem = stem
            self.leaf = leaf
        }

        public static let finished = Drawing(w: 1, bar: 1, stem: 1, leaf: 1)
    }

    public var body: some View {
        let s = size * 0.12
        ZStack {
            WShape().trim(from: 0, to: drawing.w)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: s, lineCap: .round, lineJoin: .round))
            // The gap shares the stem's path and trim, so while the stem grows up it cuts the W just ahead of its tip.
            StemShape().trim(from: 0, to: drawing.stem)
                .stroke(Color.black, style: StrokeStyle(lineWidth: s * 1.9, lineCap: .round))
                .blendMode(.destinationOut)
            StemShape().trim(from: 0, to: drawing.stem)
                .stroke(Palette.text, style: StrokeStyle(lineWidth: s, lineCap: .round))
            // Both halves start at the stem top, so the branch grows out both ways at once.
            ForEach(BranchShape.halves.indices, id: \.self) { i in
                BranchShape.halves[i].trim(from: 0, to: drawing.bar)
                    .stroke(Palette.text, style: StrokeStyle(lineWidth: s, lineCap: .round))
            }
            // The leaf unfolds from its base on the branch end: it grows from a tenth of its size, turning up 45°.
            LeafShape().fill(Palette.accent)
                .scaleEffect(0.1 + 0.9 * drawing.leaf, anchor: LeafShape.base)
                .rotationEffect(.degrees(45 * (1 - drawing.leaf)), anchor: LeafShape.base)
                .opacity(drawing.leaf > 0 ? 1 : 0)
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

    /// Vertical line at the centre, from the W's baseline (0.90) up to the branch (0.14), so a trim grows it upwards.
    private struct StemShape: Shape {
        func path(in r: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.90))
            path.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * BranchShape.top))
            return path
        }
    }

    /// One half of the branch: a cubic from the stem top out to one end. The halves share the tangent at the stem top,
    /// so together they read as one soft wave; the right half is shorter and ends under the leaf.
    private struct BranchShape: Shape {
        static let top: CGFloat = 0.14
        static let halves = [
            BranchShape(c1: (0.40, 0.08), c2: (0.24, 0.08), end: (0.12, 0.16)),
            BranchShape(c1: (0.58, 0.20), c2: (0.66, 0.22), end: (0.74, 0.20)),
        ]

        var c1: (x: CGFloat, y: CGFloat)
        var c2: (x: CGFloat, y: CGFloat)
        var end: (x: CGFloat, y: CGFloat)

        func path(in r: CGRect) -> Path {
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
            var path = Path()
            path.move(to: p(0.5, Self.top))
            path.addCurve(to: p(end.x, end.y), control1: p(c1.x, c1.y), control2: p(c2.x, c2.y))
            return path
        }
    }

    /// A filled leaf from its base on the branch end (0.72, 0.21) up to its tip (0.96, 0.03).
    private struct LeafShape: Shape {
        static let base = UnitPoint(x: 0.72, y: 0.21)

        func path(in r: CGRect) -> Path {
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
            var path = Path()
            path.move(to: p(0.72, 0.21))
            path.addCurve(to: p(0.96, 0.03), control1: p(0.74, 0.08), control2: p(0.84, 0.03))
            path.addCurve(to: p(0.72, 0.21), control1: p(0.95, 0.15), control2: p(0.86, 0.23))
            path.closeSubpath()
            return path
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
