import SwiftUI
import ToriUI

/// Launch animation over the root view. The mark draws in (the W, then the T bar, then the stem cutting the W); if the
/// data is still loading, a dim band sweeps across it until the launch finishes; then it fades out, with a soft haptic
/// only when the user had to wait. The system launch screen is only the `LaunchBackground` colour, so this view's first
/// frame (background, nothing drawn) matches it.
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
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: leaving) { _, leaving in
                leaving && waitStart != nil
            }
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
            drawn = true
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { w = 1 }
        withAnimation(.spring(duration: 0.22, bounce: 0.35).delay(0.3)) { bar = 1 }
        withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.28).delay(0.44)) { stem = 1 }
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
