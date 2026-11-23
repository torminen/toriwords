import CoreHaptics
import SwiftUI
import ToriUI

/// Launch animation over the root view. The mark draws in (the W, then the T bar, then the stem cutting the W, with a
/// rolling haptic that ends as the stem lands); if the data is still loading, a dim band sweeps across it until the
/// launch finishes; then it fades out. The system launch screen is only the `LaunchBackground` colour, so this view's
/// first frame (background, nothing drawn) matches it.
struct LaunchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var w: CGFloat = 0
    @State private var bar: CGFloat = 0
    @State private var stem: CGFloat = 0
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
                    LogoMark(size: markSize, drawing: .init(w: w, bar: bar, stem: stem))
                        .mask { sheen(at: context.date) }
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

    private func draw() async {
        if reduceMotion {
            (w, bar, stem) = (1, 1, 1)
            LaunchHaptic.play(endingIn: 0)
            drawn = true
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { w = 1 }
        withAnimation(.spring(duration: 0.22, bounce: 0.35).delay(0.3)) { bar = 1 }
        let (stemDelay, stemDuration) = (0.44, 0.28)
        withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: stemDuration).delay(stemDelay)) { stem = 1 }
        LaunchHaptic.play(endingIn: stemDelay + stemDuration)
        try? await Task.sleep(for: .milliseconds(800))
        drawn = true
    }

    private func leave() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.3)) {
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
