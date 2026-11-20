import SwiftUI
import ToriUI

/// How to add the Home Screen widget: on the Add screen after a save, and in Settings → Widget.
struct WidgetHint: View {
    /// "Not now" button; nil hides it.
    var notNow: (() -> Void)?

    var body: some View {
        Banner(.tip, title: Text("Add the ToriWords widget"),
               message: Text("Today's cards on your Home Screen: touch and hold an empty area, tap Edit → Add Widget, then find ToriWords.")) {
            if let notNow { Button("Not now", action: notNow).buttonStyle(.borderless) }
        }
    }
}

/// Settings → Widget.
struct WidgetView: View {
    var body: some View {
        List {
            Section {
                WidgetHint()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Text("Widget"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
