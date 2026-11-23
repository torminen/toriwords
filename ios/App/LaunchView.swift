import CoreHaptics
import SwiftUI
import ToriUI

/// Launch animation over the root view. The mark grows in (the W, then the T stem rising through it, then the branch
/// unfurling from the stem top, then the leaf unfolding on its end, with a rolling haptic that ends as the leaf opens)
/// and holds briefly, even when the data is ready; if the data is still loading, a dim band sweeps across it until the
/// launch finishes; then it fades out. The system launch screen is only the `LaunchBackground` colour, so this view's
/// first frame (background, nothing drawn) matches it.
struct LaunchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var w: CGFloat = 0
    @State private var bar: CGFloat = 0
    @State private var stem: CGFloat = 0
    @State private var leaf: CGFloat = 0
    /// Reduce Motion only: the mark fades in instead of drawing.
    @State private var shown = false
    @State private var drawn = false
    @State private var waitStart: Date?
    @State private var leaving = false
    @State private var finished = false

    private let markSize: CGFloat = 150

    var body: some View {
        if !finished {
            ZStack {
                Palette.background
                TimelineView(.animation(paused: waitStart == nil || reduceMotion)) { context in
                    LogoMark(size: markSize, drawing: .init(w: w, bar: bar, stem: stem, leaf: leaf))
                        .mask { sheen(at: context.date) }
                        .opacity(reduceMotion && !shown ? 0 : 1)
                }
            }
            .ignoresSafeArea()
            .opacity(leaving ? 0 : 1)
            .offset(y: leaving && !reduceMotion ? -8 : 0)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "ToriWords"))
            .task { await draw() }
            .onChange(of: drawn) { _, drawn in
                if drawn && env.phase == .launching { waitStart = .now }
            }
            .onChange(of: drawn && env.phase != .launching) { _, done in
                if done { leave() }
            }
        }
    }

    /// Strong ease-out, cubic-bezier(0.23, 1, 0.32, 1): for the W (already there, it just appears) and the exit.
    private static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    /// cubic-bezier(0.4, 0, 0.2, 1): a gentle start and a long settle, so the tree reads as growing rather than bursting
    /// out of the ground. A deliberate exception to ease-out: this is a one-off brand moment, not a UI response.
    private static func growth(_ duration: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: duration) }
    /// The finished mark holds this long before the launch may leave, even when the data is already loaded.
    private static let hold: Duration = .milliseconds(400)

    private func draw() async {
        if reduceMotion {
            // No drawing movement: the finished mark fades in.
            (w, bar, stem, leaf) = (1, 1, 1, 1)
            withAnimation(Self.easeOut(0.25)) { shown = true }
            LaunchHaptic.play(endingIn: 0.25)
            try? await Task.sleep(for: .milliseconds(250) + Self.hold)
            drawn = true
            return
        }
        withAnimation(Self.easeOut(0.5)) { w = 1 }
        // The tree grows: the stem rises through the W (the grass), then the branch unfurls from its top as the stem
        // nears it (at 0.85 s the stem is ~95 % up).
        withAnimation(Self.growth(0.7).delay(0.3)) { stem = 1 }
        withAnimation(Self.growth(0.55).delay(0.85)) { bar = 1 }
        // The leaf is the last accent: it unfolds as the branch reaches its end.
        let (leafDelay, leafDuration) = (1.25, 0.45)
        withAnimation(Self.growth(leafDuration).delay(leafDelay)) { leaf = 1 }
        // The roll ends as the leaf has visibly opened (about 70 % of its duration on this curve).
        LaunchHaptic.play(endingIn: leafDelay + leafDuration * 0.7)
        try? await Task.sleep(for: .seconds(leafDelay + leafDuration) + Self.hold)
        drawn = true
    }

    private func leave() {
        withAnimation(Self.easeOut(reduceMotion ? 0.2 : 0.3)) {
            leaving = true
        } completion: {
            finished = true
        }
    }

    /// Mask with a dim band (40 % opacity) that sweeps across the mark: a 1.1 s pass, then a 0.5 s pause. The band sits
    /// off the mark until the wait starts.
    private func sheen(at date: Date) -> some View {
        var x: CGFloat = -0.8
        if let waitStart, !reduceMotion {
            let p = min(date.timeIntervalSince(waitStart).truncatingRemainder(dividingBy: 1.6) / 1.1, 1)
            x = -0.8 + 1.6 * p * p * (3 - 2 * p)
        }
        return LinearGradient(stops: [
            .init(color: .white, location: 0.44),
            .init(color: .white.opacity(0.4), location: 0.5),
            .init(color: .white, location: 0.56),
        ], startPoint: .leading, endPoint: .trailing)
            .frame(width: markSize * 3)
            .offset(x: x * markSize)
    }
}

/// A short roll: taps that swell and fade, like something rolling over a bump. Tune the taps to taste.
@MainActor
private enum LaunchHaptic {
    /// (time s, intensity 0…1). Sharpness is low throughout so the taps blur into one movement.
    private static let taps: [(time: TimeInterval, intensity: Float)] = [
        (0, 0.35), (0.04, 0.6), (0.08, 0.85), (0.12, 1), (0.17, 0.75), (0.23, 0.45), (0.3, 0.2),
    ]
    private static let sharpness: Float = 0.25
    /// Held so the engine outlives the call; auto-shutdown stops it once the pattern ends.
    private static var engine: CHHapticEngine?

    /// Schedules the roll so its last tap lands `end` seconds from now (or plays it at once if it is longer than that).
    static func play(endingIn end: TimeInterval) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let events = taps.map {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: $0.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: $0.time)
        }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let start = max(0, end - (taps.last?.time ?? 0))
            try engine.makePlayer(with: pattern).start(atTime: engine.currentTime + start)
            self.engine = engine
        } catch {
            // Haptics are a nicety; the launch goes on without them.
        }
    }
}
