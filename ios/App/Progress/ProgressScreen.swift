import Charts
import Observation
import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Progress (doc 35 §3.9, wireframe 9-4 P1; Product §5.15; doc 36 §14.1). No XP, levels or streaks.
struct ProgressScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    let store: ToriStore

    @State private var summary: ProgressSummary?
    @State private var isEmpty = false

    var body: some View {
        Group {
            if isEmpty {
                // The vocabulary emptied while the screen was open (U2).
                EmptyStateView(title: Text("Build your vocabulary"),
                               message: Text("Words you add come back for review just before you forget them."),
                               actionTitle: Text("Add a word")) { router.push(.add(text: nil)) }
            } else if let summary {
                content(summary)
            } else {
                Color.clear
            }
        }
        .background(Palette.background)
        .navigationTitle(Text("Progress"))
        .navigationBarTitleDisplayMode(.inline)
        // Restarted when the app becomes active, so "today" is re-read after the 04:00 day start.
        .task(id: scenePhase == .active) {
            let values = store.observe { try $0.progress(now: Now.ms, utcOffsetMin: Now.utcOffsetMin) }
            do {
                for try await value in values {
                    summary = value
                    let v = value.vocabulary
                    isEmpty = v.new + v.learning + v.knownWell + v.alreadyKnown + v.paused == 0
                }
            } catch {}
        }
    }

    private func content(_ s: ProgressSummary) -> some View {
        List {
            Section {
                HStack(spacing: Spacing.s) {
                    Tile(value: s.today.cardsReviewed, label: Text("reviewed"))
                    Tile(value: s.today.toReview + s.today.new, label: Text("still due"))
                    Tile(value: s.today.newWordsIntroduced, label: Text("new words"))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: { Text("Today") }

            Section {
                vocabularyRow(Text(Strings.stageNew), s.vocabulary.new, .new)
                vocabularyRow(Text(Strings.stageLearning), s.vocabulary.learning, .learning)
                vocabularyRow(Text(Strings.stageKnownWell), s.vocabulary.knownWell, .knownWell)
                vocabularyRow(Text("Already known"), s.vocabulary.alreadyKnown, .known)
                vocabularyRow(Text(Strings.stagePaused), s.vocabulary.paused, .paused)
            } header: { Text("Vocabulary") }

            Section {
                BarChart(values: s.activity, unitDays: 1, label: Text("Reviews"))
            } header: { Text("Activity") } footer: { Text("Reviews per day, last 30 days") }

            Section {
                BarChart(values: s.capturedPerWeek, unitDays: 7, label: Text("Words added"))
            } header: { Text("Captured") } footer: { Text("Words added per week, last 8 weeks") }

            if !s.topSources.isEmpty {
                Section {
                    ForEach(s.topSources, id: \.id) { source in
                        LabeledContent { Text(verbatim: "\(source.entryCount)") } label: { Text(verbatim: source.label) }
                    }
                } header: { Text("Top sources") }
            }
        }
    }

    private func vocabularyRow(_ title: Text, _ count: Int, _ stage: WordStage) -> some View {
        DrillRow(title: title, value: Text(verbatim: "\(count)")) {
            router.push(.words(WordsQuery(filter: .stage(stage))))
        }
    }
}

private struct Tile: View {
    let value: Int
    let label: Text

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(verbatim: "\(value)").font(Typography.cardTranslation).monospacedDigit()
            label.font(Typography.secondary).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.cell, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Oldest-first counts ending today; each bar is `unitDays` long and dated by its last day.
private struct BarChart: View {
    let values: [Int]
    let unitDays: Int
    let label: Text

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        Chart(Array(values.enumerated()), id: \.offset) { item in
            BarMark(x: .value("Day", day(item.offset, today: today), unit: unitDays == 7 ? .weekOfYear : .day),
                    y: .value("Count", item.element))
                .foregroundStyle(Palette.accent)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 140)
        .accessibilityLabel(label)
    }

    private func day(_ index: Int, today: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -(values.count - 1 - index) * unitDays, to: today) ?? today
    }
}
