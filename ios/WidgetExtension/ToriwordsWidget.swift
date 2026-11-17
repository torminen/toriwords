import SwiftUI
import WidgetKit

// Placeholder; the four widget families arrive in plan step 10.
@main
struct ToriwordsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "due", provider: Provider()) { _ in Text("ToriWords") }
            .configurationDisplayName("ToriWords")
    }
}

private struct Provider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}
