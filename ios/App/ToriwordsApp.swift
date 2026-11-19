import SwiftUI
import Translation
import ToriUI

@main
struct ToriwordsApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        let env = env
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.router)
                .environment(env.deletion)
                .tint(Palette.accent)
                .onOpenURL { env.open($0) }
        }
        // Registered at launch by SwiftUI; expiration cancels the task (§10.4).
        .backgroundTask(.appRefresh(AppConfig.backgroundRefreshTaskID)) { await env.backgroundRefresh() }
    }
}

/// Runs the launch sequence before any data is shown, hosts the Home stack and the Review cover, the hidden
/// `.translationTask` for background fills (§6.3), and the scene-phase handling (§3, §7.8).
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = env.router
        Group {
            switch env.phase {
            case .launching:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
            case .failed(let message):
                EmptyStateView(title: Text("ToriWords could not open its data"), message: Text(verbatim: message))
            case .ready:
                if let store = env.store {
                    NavigationStack(path: $router.path) {
                        HomeView(store: store)
                            .navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }
                    .overlay(alignment: .bottom) { UndoToast().animation(.default, value: env.deletion.current) }
                    .fullScreenCover(isPresented: $router.isReviewPresented) {
                        ReviewView(store: store)
                    }
                }
            }
        }
        .translationTask(env.translationBridge.configuration) { session in
            await env.translationBridge.serve(session)
        }
        .task { await env.launch() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: env.didBecomeActive()
            case .background: env.didEnterBackground()
            default: break
            }
        }
    }
}
