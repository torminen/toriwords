#if canImport(SwiftUI)
import SwiftUI
import ToriCore

/// Review card container: front and back on one surface, flipped around the vertical axis.
/// Taps and swipes stay with the caller; only the visible side is exposed to VoiceOver.
public struct FlipCard<Front: View, Back: View>: View {
    public var isFlipped: Bool
    private let front: Front
    private let back: Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isFlipped: Bool, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.isFlipped = isFlipped
        self.front = front()
        self.back = back()
    }

    public var body: some View {
        ZStack {
            front
                .opacity(isFlipped ? 0 : 1)
                .accessibilityHidden(isFlipped)
            back
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
                .accessibilityHidden(!isFlipped)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .rotation3DEffect(.degrees(reduceMotion ? 0 : (isFlipped ? 180 : 0)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.35), value: isFlipped)
    }
}

/// A Context sentence with the Entry text emphasised (recognition, card back) or blanked as "______" (recall front).
/// In `.blank` style a sentence without a usable highlight renders nothing: the recall front then shows the
/// translation only and must not leak the answer.
public struct SentenceText: View {
    public enum Style: Sendable { case highlight, blank }

    public var sentence: String
    public var highlight: Capture.Highlight?
    public var style: Style

    public init(_ sentence: String, highlight: Capture.Highlight?, style: Style = .highlight) {
        self.sentence = sentence
        self.highlight = highlight
        self.style = style
    }

    public var body: some View {
        let markup = SentenceMarkup(sentence: sentence, highlight: highlight)
        switch (style, markup) {
        case (.blank, nil):
            EmptyView()
        case (.blank, let m?):
            Text(verbatim: "\u{201C}\(m.blanked)\u{201D}")
                .accessibilityLabel(Text(verbatim: m.before + String(localized: Self.blankLabel) + m.after))
        case (.highlight, nil):
            Text(verbatim: "\u{201C}\(sentence)\u{201D}")
        case (.highlight, let m?):
            Text(Self.emphasised(m))
        }
    }

    static let blankLabel = LocalizedStringResource("ui.sentence.blank", defaultValue: "blank")

    static func emphasised(_ m: SentenceMarkup) -> AttributedString {
        var word = AttributedString(m.word)
        word.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString("\u{201C}" + m.before) + word + AttributedString(m.after + "\u{201D}")
    }
}

#Preview("Flip card") {
    @Previewable @State var flipped = false
    FlipCard(isFlipped: flipped) {
        VStack(spacing: Spacing.l) {
            Spacer()
            Text(verbatim: "thorough").font(Typography.cardWord)
            SentenceText("The police carried out a thorough search of the house.", highlight: .init(offset: 25, length: 8))
                .font(Typography.body).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            Spacer()
            Text(LocalizedStringResource("ui.card.tapToShow", defaultValue: "Tap to show answer"))
                .font(Typography.secondary).foregroundStyle(Palette.textSecondary)
        }
    } back: {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(verbatim: "thorough").font(Typography.cardWord)
            Text(verbatim: "/ˈθʌr.ə/ · adjective").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            Text(verbatim: "тщательный, основательный").font(Typography.heading)
            Divider()
            SentenceText("The police carried out a thorough search of the house.", highlight: .init(offset: 25, length: 8),
                         style: .blank)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .background(Palette.background)
    .onTapGesture { flipped.toggle() }
}
#endif
