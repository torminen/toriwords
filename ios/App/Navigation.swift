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
        // TODO(9b): Add, Words, Entry read/edit.
        case .add: PlaceholderScreen(title: "Add", step: "9b")
        case .words: PlaceholderScreen(title: "Words", step: "9b")
        case .entry: PlaceholderScreen(title: "Word", step: "9b")
        case .entryEdit: PlaceholderScreen(title: "Edit", step: "9b")
        case .progress: ProgressScreen(store: store)
        case .settings: SettingsView(store: store)
        case .newWordsPerDay: NewWordsPerDayView(store: store)
        case .accent: AccentView()
        case .translation: TranslationView()
        case .language: LanguageView()
        case .account: AccountView(store: store)
        case .data: DataView(store: store)
        case .export: ExportView(store: store)
        case .tags: PlaceholderScreen(title: "Tags", step: "9b")
        case .about: AboutView()
        }
    }
}

/// TODO(9b/9c): temporary destination until the screen's step lands. Not localised on purpose.
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
