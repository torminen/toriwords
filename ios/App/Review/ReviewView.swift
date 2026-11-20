import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Review session, presented full screen. It has its own
/// navigation stack so ••• Edit returns to the same card.
struct ReviewView: View {
    let store: ToriStore
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var model: ReviewModel?
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model { ReviewContent(model: model, path: $path) } else { Palette.background }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        // The cover hides the root stack's toast, so the Undo for deletes made in Review shows here.
        .overlay(alignment: .bottom) { UndoToast().animation(.default, value: env.deletion.current) }
        .task {
            guard model == nil else { return }
            let m = ReviewModel(store: store, env: env, isPractice: router.isPractice)
            model = m
            m.start()
        }
        .onChange(of: path.isEmpty) { _, isEmpty in if isEmpty { model?.reloadCurrent() } }
    }
}

private struct ReviewContent: View {
    @Bindable var model: ReviewModel
    @Binding var path: [Route]
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: Spacing.l) {
            header
            switch model.screen {
            case .loading:
                Spacer()
            case .card(let content):
                CardSession(model: model, content: content, path: $path)
            case .allDone(let summary, let next, let canLearnMore):
                Finished(title: Text("All done for today"),
                         detail: Text("\(summary.reviewed) cards reviewed · \(summary.remembered) remembered · \(summary.newWords) new words"),
                         next: next, canLearnMore: canLearnMore, model: model, done: close)
            case .nothingDue(let next, let canLearnMore):
                Finished(title: Text("Nothing to review today"), detail: nil, next: next, canLearnMore: canLearnMore,
                         model: model, done: close)
            case .practiceDone(let summary):
                Finished(title: Text("Practice done"),
                         detail: Text("\(summary.reviewed) cards · \(summary.remembered) remembered"),
                         next: nil, canLearnMore: false, model: model, done: close)
            case .nothingAdded:
                Spacer()
                EmptyStateView(title: Text("Add words to start reviewing"), actionTitle: Text("Add a word")) {
                    close()
                    router.push(.add(text: nil))
                }
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
        .background(Palette.background)
        .sheet(isPresented: $model.showReminderOffer) {
            ReminderOfferSheet { hour, minute in Task { await env.reminders?.enableDailyReminder(hour: hour, minute: minute) } }
        }
        .alert(Text("Something went wrong"), isPresented: Binding(get: { model.errorMessage != nil },
                                                                 set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }

    private var header: some View {
        ZStack {
            if case .card = model.screen {
                Group {
                    if model.isPractice { Text("Practice · \(model.position) / \(model.total)") }
                    else { Text(verbatim: "\(model.position) / \(model.total)") }
                }
                .font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                .accessibilityLabel(Text("Card \(model.position) of \(model.total)"))
            }
            HStack(spacing: Spacing.l) {
                Button(action: close) { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Close"))
                if model.canUndo {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .accessibilityLabel(Text("Undo last answer"))
                }
                Spacer()
                if case .card(let c) = model.screen, model.isFlipped {
                    CardMenu(model: model, word: c.word) { path.append(.entryEdit(c.card.entry)) }
                }
            }
            .font(.title3)
        }
        .frame(minHeight: 44)
    }

    /// ✕: leaves immediately, no confirmation; given answers are kept.
    private func close() {
        model.close()
        router.isReviewPresented = false
    }
}

// MARK: Card

private struct CardSession: View {
    let model: ReviewModel
    let content: CardContent
    @Binding var path: [Route]
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragX: CGFloat = 0
    @State private var demoX: CGFloat = 0
    /// The answered card is flying off; further swipes and taps on the grade buttons are ignored until it is gone.
    @State private var isFlying = false
    /// Decided by the first movement of a drag: only a horizontal drag moves the card; a vertical one scrolls the back.
    @State private var isHorizontalDrag: Bool?

    /// The card tilts one degree per this many points of drag.
    static let pointsPerDegree: CGFloat = 15
    /// Released at this tilt or more, the card grades; less, it springs back upright.
    static let gradeAngle: Double = 10
    static func angle(_ x: CGFloat) -> Double { Double(x / pointsPerDegree) }
    /// Far enough that the tilted card is fully off screen.
    private static let flyOffDistance: CGFloat = 1000
    /// One spring for springing back, flying off and the next card growing in.
    private static let springDuration = 0.35
    private static let springBounce = 0.4

    var body: some View {
        let x = dragX + demoX
        VStack(spacing: Spacing.l) {
            FlipCard(isFlipped: model.isFlipped) {
                CardFront(model: model, content: content)
            } back: {
                CardBack(model: model, content: content)
            }
            // Inside the offset and rotation, so the label travels and tilts with the card.
            // One label per side, always present: switching one label's side as x crosses 0 (the spring back
            // overshoots) would slide it across the card.
            .overlay(alignment: .leading) { SwipeLabel(rating: .remembered, x: x) }
            .overlay(alignment: .trailing) { SwipeLabel(rating: .forgot, x: x) }
            .offset(x: x)
            .rotationEffect(.degrees(Self.angle(x)))
            .contentShape(Rectangle())
            .onTapGesture { model.flip() }
            // Simultaneous: the back's ScrollView would otherwise take drags that start on its content.
            .simultaneousGesture(drag, including: model.isFlipped ? .all : .subviews)
            .accessibilityAction { model.flip() }
            .id(content.card.id)
            // The next card grows in; the answered one has already flown off screen.
            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .identity))

            HStack(spacing: Spacing.m) {
                Button { grade(.forgot) } label: { Text(Strings.forgot) }
                    .buttonStyle(.toriPrimary(tint: Palette.danger))
                Button { grade(.remembered) } label: { Text(Strings.remembered) }
                    .buttonStyle(.toriPrimary(tint: Palette.success))
            }
            .opacity(model.isFlipped ? 1 : 0)
            .disabled(!model.isFlipped)
            .accessibilityHidden(!model.isFlipped)
        }
        .task(id: model.isFlipped) { await swipeDemoIfFirst() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { v in
                guard !isFlying else { return }
                if isHorizontalDrag == nil { isHorizontalDrag = abs(v.translation.width) > abs(v.translation.height) }
                guard isHorizontalDrag == true else { return }
                dragX = v.translation.width
            }
            .onEnded { v in
                defer { isHorizontalDrag = nil }
                guard !isFlying, isHorizontalDrag == true else { return }
                let angle = Self.angle(dragX)
                if angle >= Self.gradeAngle { grade(.remembered, velocity: v.velocity.width) }
                else if angle <= -Self.gradeAngle { grade(.forgot, velocity: v.velocity.width) }
                else { withAnimation(.spring(duration: Self.springDuration, bounce: Self.springBounce)) { dragX = 0 } }
            }
    }

    /// Swipe and buttons alike: the card flies off screen to its side with the spring it springs back with, carrying
    /// the finger's speed; only once it is gone does the next card grow in. `velocity`: points per second at release
    /// (0 for the buttons, so the card accelerates from rest). Not reduced for Reduce Motion: it continues the user's
    /// own drag (the demo and the flip are).
    private func grade(_ rating: Rating, velocity: CGFloat = 0) {
        guard !isFlying else { return }
        isFlying = true
        let target = rating == .remembered ? Self.flyOffDistance : -Self.flyOffDistance
        // A spring's initial velocity is relative: the fraction of the remaining distance covered per second.
        let relative = min(max(velocity / (target - dragX), 0), 8)
        withAnimation(.interpolatingSpring(duration: Self.springDuration, bounce: 0, initialVelocity: relative)) {
            dragX = target
        } completion: {
            isFlying = false
            withAnimation(.spring(duration: Self.springDuration, bounce: Self.springBounce)) {
                dragX = 0
                model.grade(rating)
            }
        }
    }

    /// Once, on the first flipped card ever: nudge right (Remembered), then left (Forgot), spring back.
    private func swipeDemoIfFirst() async {
        guard model.isFlipped, !env.settings.swipeDemoShown else { return }
        env.settings.swipeDemoShown = true
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.easeInOut(duration: 0.35)) { demoX = 70 }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.easeInOut(duration: 0.45)) { demoX = -70 }
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.spring) { demoX = 0 }
    }
}

/// Mid-height, trailing the card: Remembered left of it while it moves right, Forgot right of it while it moves left.
/// Grows and fades in with the tilt toward its side, fully shown at the grading angle.
private struct SwipeLabel: View {
    let rating: Rating
    let x: CGFloat

    var body: some View {
        let remembered = rating == .remembered
        let angle = remembered ? CardSession.angle(x) : -CardSession.angle(x)
        let progress = min(max(angle, 0) / CardSession.gradeAngle, 1)
        Group {
            if remembered {
                Badge(Strings.rememberedArrow, fill: Palette.successFill, ink: Palette.success)
            } else {
                Badge(Strings.forgotArrow, fill: Palette.danger.opacity(0.15), ink: Palette.danger)
            }
        }
        .font(Typography.heading)
        .scaleEffect(0.7 + 0.3 * progress)
        .opacity(progress)
        // Outside the card, one card padding away from its edge; it follows the card at the same tilt.
        .alignmentGuide(remembered ? .leading : .trailing) { remembered ? $0.width + Spacing.xl : -Spacing.xl }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension Strings {
    static let rememberedArrow = LocalizedStringResource("Remembered →")
    static let forgotArrow = LocalizedStringResource("← Forgot")
}

private struct CardFront: View {
    let model: ReviewModel
    let content: CardContent

    var body: some View {
        VStack(spacing: Spacing.xl) {
            switch content.direction {
            case .recognition:
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(verbatim: content.word).font(Typography.cardWord).multilineTextAlignment(.center)
                    SpeakButton(content.word, sentence: content.frontSentence?.text)
                }
                sentence(.highlight)
                Spacer()
            case .recall:
                // UQ-3 closed: no speaker on the recall front; the hint stays.
                Text("Say it in English").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                Spacer()
                translations
                sentence(.blank)
                Spacer()
            case .cloze:
                Spacer()
                if content.frontSentence != nil {
                    sentence(.blank).font(Typography.cardTranslation).foregroundStyle(Palette.text)
                    Text("Fill in the missing word").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                } else {
                    translations
                }
                Spacer()
            }
            Text(Strings.tapToShow).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityHint(Text(Strings.tapToShow))
    }

    private var translations: some View {
        Text(verbatim: content.translations.joined(separator: ", ")).font(Typography.cardTranslation)
    }

    @ViewBuilder
    private func sentence(_ style: SentenceText.Style) -> some View {
        if let s = content.frontSentence {
            ScrollView {
                SentenceText(s.text, highlight: s.highlight, style: style)
                    .font(Typography.body).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 200)
        }
    }
}

private extension Strings {
    static let tapToShow = LocalizedStringResource("ui.card.tapToShow", defaultValue: "Tap to show answer")
}

private struct CardBack: View {
    let model: ReviewModel
    let content: CardContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: content.word).font(Typography.cardWord)
                    Spacer()
                    SpeakButton(content.word, sentence: content.backSentence?.text)
                }
                let detail = [content.ipa, content.partOfSpeech].compactMap { $0 }.filter { !$0.isEmpty }
                if !detail.isEmpty {
                    Text(verbatim: detail.joined(separator: " · ")).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
                if !content.translations.isEmpty {
                    Text(verbatim: content.translations.joined(separator: ", ")).font(Typography.heading)
                }
                ForEach(Array(content.definitions.enumerated()), id: \.offset) {
                    Text(verbatim: $0.element).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
                if let s = content.backSentence {
                    Divider().padding(.vertical, Spacing.s)
                    HStack(alignment: .firstTextBaseline) {
                        SentenceText(s.text, highlight: s.highlight).font(Typography.body)
                        Spacer()
                        SpeakButton(s.text)
                            .accessibilityLabel(Text("Play sentence"))
                    }
                    if let source = s.source {
                        Text(verbatim: "— \(source)").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// ••• on the back: Edit, I already know this, Pause, Delete.
private struct CardMenu: View {
    let model: ReviewModel
    let word: String
    let edit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        Menu {
            Button("Edit", systemImage: "pencil", action: edit)
            Button("I already know this", systemImage: "checkmark") { model.setStatus(.known) }
            Button("Pause", systemImage: "pause") { model.setStatus(.paused) }
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text("More"))
        .alert(Text("Delete “\(word)”?"), isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed with its review history on all your devices.")
        }
    }
}

// MARK: End states

private struct Finished: View {
    let title: Text
    let detail: Text?
    let next: Int?
    let canLearnMore: Bool
    let model: ReviewModel
    let done: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            Spacer()
            title.font(Typography.cardWord).multilineTextAlignment(.center)
            detail?.font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            if let next = NextReview.text(inDays: next) {
                Text(next).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if canLearnMore {
                Button("Learn more new words") { model.learnMore() }.buttonStyle(.toriSecondary)
            }
            Button("Done", action: done).font(Typography.heading).frame(minHeight: 44)
        }
        .multilineTextAlignment(.center)
    }
}

/// After the first finished session ever (1-10 iOS 7). Scheduling itself is the reminders step (9d).
private struct ReminderOfferSheet: View {
    let turnOn: (_ hour: Int, _ minute: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Remind you to review every day?").font(Typography.heading)
            Text("Only on days when cards are due. No streaks.").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            DatePicker(selection: $time, displayedComponents: .hourAndMinute) { Text("Reminder time") }
                .padding(Spacing.m)
                .background(Palette.neutralFill, in: RoundedRectangle(cornerRadius: Radius.cell, style: .continuous))
            Button("Turn on reminder") {
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                turnOn(c.hour ?? 19, c.minute ?? 0)
                dismiss()
            }
            .buttonStyle(.toriPrimary)
            Button("Not now") { dismiss() }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(Spacing.xl)
        .presentationDetents([.medium])
    }
}
