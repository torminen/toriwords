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
        switch route {
        case .add(let text): if let store = env.store { AddView(store: store, initialText: text) }
        case .words(let q): if let store = env.store { WordsView(store: store, query: q) }
        case .entry(let id): if let store = env.store { EntryView(store: store, id: id) }
        case .entryEdit(let id): if let store = env.store { EntryView(store: store, id: id, editOnly: true) }
        // TODO(9c): Progress, Settings and drill-ins, Account, Data, Export, About.
        case .progress: PlaceholderScreen(title: "Progress", step: "9c")
        case .settings: PlaceholderScreen(title: "Settings", step: "9c")
        case .newWordsPerDay: PlaceholderScreen(title: "New words per day", step: "9c")
        case .accent: PlaceholderScreen(title: "Accent", step: "9c")
        case .translation: PlaceholderScreen(title: "Translation", step: "9c")
        case .language: PlaceholderScreen(title: "Language", step: "9c")
        case .account: PlaceholderScreen(title: "Account", step: "9c")
        case .data: PlaceholderScreen(title: "Data", step: "9c")
        case .export: PlaceholderScreen(title: "Export", step: "9c")
        case .tags: if let store = env.store { TagsView(store: store) }
        case .about: PlaceholderScreen(title: "About", step: "9c")
        }
    }
}

/// TODO(9c): temporary destination until the screen's step lands. Not localised on purpose.
private struct PlaceholderScreen: View {
    let title: String
    let step: String

    var body: some View {
        Text(verbatim: "\(title) — step \(step)")
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
    }
}
