import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Home screen.
struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PendingDeletion.self) private var deletion
    @State private var model: HomeModel

    init(store: ToriStore) { _model = State(initialValue: HomeModel(store: store)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                addField
                if let s = model.snapshot {
                    if s.state == .empty {
                        FirstRunCard { router.push(.add(text: nil)) }
                    } else {
                        DueTodayBlock(snapshot: s)
                        // Rows pending deletion are hidden during the Undo window.
                        recentlyAdded(s.recent.filter { !deletion.hidden.contains($0.id) })
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.s)
        }
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { BrandHeader() }.hidingSharedBackground()
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Words") { router.push(.words(WordsQuery())) }
                Button { router.push(.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(Text("Settings"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Restarted when the app becomes active, so "today" is re-read after midnight / 04:00.
        .task(id: scenePhase == .active) { await model.observe() }
    }

    private var addField: some View {
        Button { router.push(.add(text: nil)) } label: {
            Text("Add a word…")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, Spacing.m)
                .background(Palette.neutralFill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func recentlyAdded(_ rows: [WordRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Recently added").font(Typography.heading).accessibilityAddTraits(.isHeader)
                ForEach(rows, id: \.id) { row in
                    Button { router.push(.entry(row.id)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.text).font(Typography.body.weight(.semibold)).foregroundStyle(Palette.text)
                            TranslationLine.text(row.translation)
                                .font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Button { router.push(.words(WordsQuery())) } label: {
            Text("All words ›").font(Typography.body)
        }
    }
}

/// Second line of a word row: the translation state.
enum TranslationLine {
    static func text(_ state: TranslationState) -> Text {
        switch state {
        case .has(let t): Text(verbatim: t)
        case .notFound: Text("No translation found — add your own")
        case .pending: Text("Translation pending")
        case .none: Text("No translation yet")
        }
    }
}

/// "Next review: tomorrow" / "in N days": always a day, never a time.
enum NextReview {
    static func text(inDays days: Int?) -> LocalizedStringResource? {
        guard let days, days > 0 else { return nil }
        return days == 1 ? "Next review: tomorrow" : "Next review: in \(days) days"
    }
}

// MARK: Due today

/// The Due today block: one tap target opening Progress (or the Needs translation filter), with Review as a separate
/// button; the catch-up message is shown inside it.
private struct DueTodayBlock: View {
    let snapshot: HomeSnapshot
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Button(action: open) { summary.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(snapshot.state == .noneReviewable ? Text("Opens words that need a translation.")
                                                                     : Text("Opens your progress."))
                .accessibilityAddTraits(.isButton)
            if snapshot.state == .due {
                Button("Review") { router.openReview() }
                    .buttonStyle(.toriPrimary)
                    .accessibilityHint(Text("Starts today's review."))
            }
        }
        .padding(Spacing.xl)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func open() {
        if snapshot.state == .noneReviewable {
            router.push(.words(WordsQuery(filter: .needsTranslation)))
        } else {
            router.push(.progress)
        }
    }

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Due today ›").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            switch snapshot.state {
            case .due:
                Text(DueCounts.text(toReview: snapshot.toReview, new: snapshot.new)).font(Typography.cardTranslation)
                if snapshot.catchUp {
                    Text("Welcome back — \(snapshot.waiting) cards are waiting. We'll spread them over about a week.")
                        .font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
            case .allDone:
                Text("All done for today").font(Typography.cardTranslation)
                if let next = NextReview.text(inDays: snapshot.nextDueInDays) {
                    Text(next).font(Typography.secondary).foregroundStyle(Palette.textSecondary)
                }
            case .nothingDue:
                Text(NextReview.text(inDays: snapshot.nextDueInDays) ?? "Nothing to review today").font(Typography.cardTranslation)
            case .noneReviewable:
                Text("\(snapshot.needsTranslation) words need a translation").font(Typography.cardTranslation)
            case .empty:
                EmptyView()
            }
        }
        .foregroundStyle(Palette.text)
    }

    private var accessibilityLabel: Text {
        let next = NextReview.text(inDays: snapshot.nextDueInDays)
        switch snapshot.state {
        case .due:
            return Text("Due today, \(String(localized: DueCounts.text(toReview: snapshot.toReview, new: snapshot.new)))")
        case .allDone:
            return next.map { Text("All done for today, \(String(localized: $0))") } ?? Text("All done for today")
        case .nothingDue:
            return next.map { Text("Due today, \(String(localized: $0))") } ?? Text("Nothing to review today")
        case .noneReviewable:
            return Text("\(snapshot.needsTranslation) words need a translation")
        case .empty:
            return Text(verbatim: "")
        }
    }
}

/// "12 to review · 5 new"; a zero part is left out.
enum DueCounts {
    static func text(toReview: Int, new: Int) -> LocalizedStringResource {
        switch (toReview, new) {
        case (0, let n): "\(n) new"
        case (let r, 0): "\(r) to review"
        case (let r, let n): "\(r) to review · \(n) new"
        }
    }
}

/// List-row style press highlight for the Due today block.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(Spacing.s)
            .background(configuration.isPressed ? Palette.neutralFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.cell, style: .continuous))
            .padding(-Spacing.s)
    }
}

// MARK: First run

/// Empty vocabulary; also the hint under the Add screen's field (without the button).
struct FirstRunCard: View {
    @Environment(AppEnvironment.self) private var env
    var add: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Build your vocabulary").font(Typography.heading)
            Text("Words you add come back for review just before you forget them.")
                .font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            Label { Text("Type it — tap “Add a word…” above") } icon: { Image(systemName: "keyboard") }
            // Share capture goes through the App Group inbox; without it (Personal builds) there is no Share Extension.
            if env.appGroup != nil {
                Label { Text("From any app — select text → Share → ToriWords") } icon: { Image(systemName: "square.and.arrow.up") }
            }
            Text("Works offline: the dictionary is built in.").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
            if let add { Button("Add your first word", action: add).buttonStyle(.toriPrimary) }
        }
        .font(Typography.body)
        .padding(Spacing.xl)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
