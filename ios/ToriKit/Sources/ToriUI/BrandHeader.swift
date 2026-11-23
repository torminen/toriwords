/// The header's gust of wind: the crown (branch and leaf) swings about the stem top on a damped spring, the leaf hangs
/// off it on a looser spring driven by the branch's acceleration (so it lags and overshoots), and the W grass leans on
/// a spring of its own. Angles are in degrees, positive clockwise; mass is 1. Kicks add to the current speed, so a tap
/// mid-swing pushes further rather than restarting.
struct SwayModel: Equatable {
    static let peak = 6.0
    static let grassPeak = 3.0
    /// How hard the branch's acceleration drives the leaf.
    static let leafCoupling = 1.2
    static let limits = (crown: 12.0, leaf: 25.0, grass: 8.0)

    private static let crownSpring = Spring(response: 0.55, damping: 0.35)
    private static let leafSpring = Spring(response: 0.55 * 0.8, damping: 0.25)
    private static let grassSpring = Spring(response: 0.4, damping: 0.45)

    var crown = 0.0, crownSpeed = 0.0
    var leaf = 0.0, leafSpeed = 0.0
    var grass = 0.0, grassSpeed = 0.0

    /// One tap: each part gets the speed that, from rest, peaks at about its `peak`.
    mutating func kick() {
        crownSpeed += Self.peak * Self.crownSpring.omega
        grassSpeed += Self.grassPeak * Self.grassSpring.omega
    }

    /// Advances by `dt` seconds in substeps of at most 1/240 s (semi-implicit Euler).
    mutating func step(_ dt: Double) {
        guard dt > 0 else { return }
        let n = (dt * 240).rounded(.up)
        let h = dt / n
        for _ in 0..<Int(n) {
            let crownAcc = Self.crownSpring.acceleration(crown, crownSpeed)
            crownSpeed += crownAcc * h
            crown = clamp(crown + crownSpeed * h, Self.limits.crown)
            leafSpeed += (Self.leafSpring.acceleration(leaf, leafSpeed) - Self.leafCoupling * crownAcc) * h
            leaf = clamp(leaf + leafSpeed * h, Self.limits.leaf)
            grassSpeed += Self.grassSpring.acceleration(grass, grassSpeed) * h
            grass = clamp(grass + grassSpeed * h, Self.limits.grass)
        }
    }

    var isSettled: Bool {
        abs(crown) + abs(crownSpeed) / 20 + abs(leaf) + abs(leafSpeed) / 20 + abs(grass) + abs(grassSpeed) / 20 < 0.01
    }

    private func clamp(_ x: Double, _ limit: Double) -> Double { min(max(x, -limit), limit) }

    private struct Spring: Equatable {
        let omega: Double, k: Double, c: Double

        /// `response` is the period in seconds and `damping` the damping fraction, as in SwiftUI's spring.
        init(response: Double, damping: Double) {
            omega = 2 * .pi / response
            k = omega * omega
            c = 2 * damping * omega
        }

        func acceleration(_ x: Double, _ v: Double) -> Double { -k * x - c * v }
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// Header layout E: 32 pt mark + 17 pt semibold "ToriWords", for the leading toolbar item (no large title).
/// The name is never truncated; text is capped at xxxLarge so it cannot crowd the trailing items.
///
/// A tap is decorative (no navigation): a gust sways the tree and grass and runs a wave along the name; every 5th tap
/// the leaf falls, and the next tap grows a new one. Reduce Motion is deliberately not checked: the movement only ever
/// follows the user's own tap on the header, it is small and local (±12°, a leaf dropping ~48 pt) and nothing else on
/// screen moves. (LaunchView keeps its Reduce Motion path: that animation plays without the user asking.)
public struct BrandHeader: View {
    public init() {}

    @State private var sway = SwayClock()
    /// The timeline runs only while something moves; at rest it is paused and there is no per-frame work.
    @State private var moving = false
    @State private var waves: [Date] = []
    @State private var drop: Drop?
    /// The leaf has fallen and the branch waits for the next tap to grow a new one.
    @State private var bare = false
    @State private var leaf: CGFloat = 1
    @State private var taps = 0
    @State private var drops = 0
    @State private var pressed = false

    private static let leafEvery = 5
    private static let fallDuration = 1.2

    public var body: some View {
        TimelineView(.animation(paused: !moving)) { context in
            let now = context.date
            let pose = sway.advance(to: now)
            let fall = drop.map { LogoMark.Fall(progress: now.timeIntervalSince($0.start) / Self.fallDuration, from: $0.from) }
            let settled = sway.model.isSettled && (fall?.progress ?? 1) >= 1
                && waves.allSatisfy { now.timeIntervalSince($0) >= Wave.duration }
            HStack(spacing: Spacing.s) {
                LogoMark(size: 32, drawing: .init(w: 1, bar: 1, stem: 1, leaf: leaf), pose: pose,
                         fall: fall.flatMap { $0.progress < 1 ? $0 : nil })
                Text(verbatim: "ToriWords").font(Typography.heading)
                    .textRenderer(WaveText(offsets: Wave.offsets(at: now, taps: waves)))
            }
            .onChange(of: settled) { _, settled in
                guard settled else { return }
                moving = false
                waves = []
                drop = nil
            }
        }
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentShape(Rectangle())
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)) { $0.scaleEffect(pressed ? 0.97 : 1) }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressed { pressed = true } }
            .onEnded { value in
                pressed = false
                if hypot(value.translation.width, value.translation.height) < 20 { tap() }
            })
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: drops)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "ToriWords"))
        .accessibilityAddTraits(.isHeader)
    }

    private func tap() {
        let now = Date.now
        taps += 1
        if !moving { sway.last = now }
        sway.model.kick()
        waves = waves.filter { now.timeIntervalSince($0) < Wave.duration } + [now]
        moving = true
        let falling = drop.map { now.timeIntervalSince($0.start) < Self.fallDuration } ?? false
        if bare {
            // Same unfold as the launch: scale 0.1 → 1, turning 45° → 0 about the base.
            bare = false
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) { leaf = 1 }
        } else if !falling && taps.isMultiple(of: Self.leafEvery) {
            // The falling copy starts from the leaf's current pose, so the leaf on the branch hides at once.
            bare = true
            leaf = 0
            drop = Drop(start: now, from: sway.pose)
            drops += 1
        }
    }

    private struct Drop {
        var start: Date
        var from: LogoMark.Pose
    }

    /// Holds the physics between frames; mutated while the timeline draws, so it is not observed.
    private final class SwayClock {
        var model = SwayModel()
        var last = Date.distantPast

        var pose: LogoMark.Pose { .init(crown: model.crown, leaf: model.leaf, grass: model.grass) }

        func advance(to now: Date) -> LogoMark.Pose {
            model.step(min(0.05, max(0, now.timeIntervalSince(last))))
            last = now
            if model.isSettled { model = SwayModel() }
            return pose
        }
    }

    /// 80 ms after a tap the letters rise 2 pt and settle, left to right, 30 ms apart, 280 ms each; waves add up.
    private enum Wave {
        static let lift: CGFloat = 2
        static let delay = 0.08, stagger = 0.03, length = 0.28, letters = 9
        static let duration = delay + stagger * Double(letters) + length

        static func offsets(at now: Date, taps: [Date]) -> [CGFloat] {
            guard !taps.isEmpty else { return [] }
            return (0..<letters).map { i in
                let y = taps.reduce(0.0) { sum, t in
                    let x = (now.timeIntervalSince(t) - delay - stagger * Double(i)) / length
                    return x <= 0 || x >= 1 ? sum : sum + pow(sin(.pi * x), 2)
                }
                return -lift * min(y, 1.5)
            }
        }
    }

    /// Moves each glyph by its offset, keeping the text's own layout and kerning.
    private struct WaveText: TextRenderer {
        var offsets: [CGFloat]

        var displayPadding: EdgeInsets { EdgeInsets(top: Wave.lift * 1.5, leading: 0, bottom: 0, trailing: 0) }

        func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
            var i = 0
            for line in layout {
                for run in line {
                    for glyph in run {
                        var c = ctx
                        if i < offsets.count { c.translateBy(x: 0, y: offsets[i]) }
                        c.draw(glyph)
                        i += 1
                    }
                }
            }
        }
    }
}
#endif
