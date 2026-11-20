import Observation
import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Every pushed screen. Sheets (tag filter, tag picker, related-word preview, share sheet), alerts and the
/// Words select mode belong to their screens; Review is a full-screen cover (`Router.isReviewPresented`).
enum Route: Hashable {
    case add(text: String?)
    case words(WordsQuery)
    case entry(ToriID)
    case entryEdit(ToriID)
    case progress
    case settings
    case newWordsPerDay
    case accent
    case translation
    case language
    case cloudSync
    case data
    case export
    case tags
    case about
    case widget
}

@MainActor @Observable
final class Router {
    var path: [Route] = []
    var isReviewPresented = false
    /// The cover runs practice instead of today's review; read once when the cover opens.
    private(set) var isPractice = false

    func push(_ route: Route) { path.append(route) }

    /// Reminder, widget and the Home Review button all land here (never Progress).
    func openReview() {
        isPractice = false
        isReviewPresented = true
    }

    /// Progress → Practice today's words.
    func openPractice() {
        isPractice = true
        isReviewPresented = true
    }
}

/// Destination for every `Route`, shared by the Home stack and the Review cover's own stack.
struct RouteView: View {
    let route: Route
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let store = env.store { destination(store) }
    }

    @ViewBuilder
    private func destination(_ store: ToriStore) -> some View {
        switch route {
        case .add(let text): AddView(store: store, initialText: text)
        case .words(let q): WordsView(store: store, query: q)
        case .entry(let id): EntryView(store: store, id: id)
        case .entryEdit(let id): EntryView(store: store, id: id, editOnly: true)
        case .progress: ProgressScreen(store: store)
        case .settings: SettingsView(store: store)
        case .newWordsPerDay: NewWordsPerDayView(store: store)
        case .accent: AccentView()
        case .translation: TranslationView()
        case .language: LanguageView()
        case .cloudSync: CloudSyncView(store: store)
        case .data: DataView(store: store)
        case .export: ExportView(store: store)
        case .tags: TagsView(store: store)
        case .about: AboutView()
        case .widget: WidgetView()
        }
    }
}
