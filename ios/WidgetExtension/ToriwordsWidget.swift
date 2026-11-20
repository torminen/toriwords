import SwiftUI
import ToriCore
import ToriShared
import ToriUI
import WidgetKit

/// Due-count widget: reads `widget-snapshot.json` only; tap opens Review.
@main
struct ToriwordsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "due", provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) { Palette.surface }
                .widgetURL(URL(string: "toriwords://review"))
        }
        .configurationDisplayName("ToriWords")
        .description("Cards to review today.")
        // The snapshot comes through the App Group; without it (Personal builds) the widget could only show "—",
        // so it offers no sizes and is not listed in the widget gallery.
        .supportedFamilies(AppGroup.shared == nil ? []
                           : [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct DueEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// "Today" is recomputed from the device offset at the entry's instant.
    var display: WidgetDisplay {
        WidgetDisplay(snapshot: snapshot, now: Int64(date.timeIntervalSince1970 * 1000),
                      utcOffsetMin: TimeZone.current.secondsFromGMT(for: date) / 60)
    }
}

struct Provider: TimelineProvider {
    private func load() -> WidgetSnapshot? { try? AppGroup.shared?.readWidgetSnapshot() }

    func placeholder(in context: Context) -> DueEntry { DueEntry(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (DueEntry) -> Void) {
        completion(DueEntry(date: .now, snapshot: load()))
    }

    /// One entry now and one per 04:00 boundary for the next 7 days (snapshot offset), then `.atEnd`.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DueEntry>) -> Void) {
        let snapshot = load()
        let now = Date.now
        let offset = snapshot?.utcOffsetMin ?? TimeZone.current.secondsFromGMT(for: now) / 60
        let boundaries = WidgetDisplay.dayBoundaries(after: Int64(now.timeIntervalSince1970 * 1000), utcOffsetMin: offset)
        let entries = [DueEntry(date: now, snapshot: snapshot)]
            + boundaries.map { DueEntry(date: Date(timeIntervalSince1970: Double($0) / 1000), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueEntry

    var body: some View {
        let display = entry.display
        switch family {
        case .accessoryCircular: circular(display)
        case .accessoryRectangular: rectangular(display)
        case .systemSmall: small(display)
        default: medium(display)
        }
    }

    private func circular(_ d: WidgetDisplay) -> some View {
        VStack(spacing: 0) {
            switch d {
            case .due(let r, let n):
                Text(verbatim: "\(r + n)").font(.title2.weight(.bold)).minimumScaleFactor(0.5)
                Text("to review").font(.system(size: 9)).minimumScaleFactor(0.5)
            case .next, .openApp:
                LogoMark(size: 22)
            }
        }
        .widgetAccentable()
    }

    private func rectangular(_ d: WidgetDisplay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "ToriWords").font(.headline).widgetAccentable()
            line(d).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ d: WidgetDisplay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LogoMark(size: 22)
            Spacer(minLength: 0)
            switch d {
            case .due(let r, let n):
                // The small widget splits the count onto two lines.
                if r > 0 { Text("\(r) to review").font(.headline) }
                if n > 0 { Text("\(n) new").font(.subheadline).foregroundStyle(Palette.textSecondary) }
            default:
                line(d).font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ d: WidgetDisplay) -> some View {
        HStack(spacing: Spacing.l) {
            LogoMark(size: 40)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                line(d).font(.headline)
                if case .due = d { Text("Tap to start reviewing").font(.subheadline).foregroundStyle(Palette.textSecondary) }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func line(_ d: WidgetDisplay) -> some View {
        switch d {
        case .due(let r, 0): Text("\(r) to review")
        case .due(0, let n): Text("\(n) new")
        case .due(let r, let n): Text("\(r) to review · \(n) new")
        case .next(_, true): Text("Next review: tomorrow")
        case .next(let day, false): Text("Next review: \(Self.date(day))")
        case .openApp: Text("Open ToriWords")
        }
    }

    /// A review-day number is the local calendar date it starts on: format it as that date, never a time.
    static func date(_ day: Int) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = TimeZone(identifier: "UTC")!
        return Date(timeIntervalSince1970: Double(day) * 86_400).formatted(style)
    }
}
