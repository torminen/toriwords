import Observation
import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Every pushed screen of doc 35 §1. Sheets (tag filter, tag picker, related-word preview, share sheet), alerts and the
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
    case account
    case data
    case export
    case tags
    case about
}

@MainActor @Observable
final class Router {
    var path: [Route] = []
    var isReviewPresented = false

    func push(_ route: Route) { path.append(route) }

    /// Reminder, widget and the Home Review button all land here (§1: never Progress).
    func openReview() { isReviewPresented = true }
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
        case .account: AccountView(store: store)
        case .data: DataView(store: store)
        case .export: ExportView(store: store)
        case .tags: TagsView(store: store)
        case .about: AboutView()
        }
    }
}
