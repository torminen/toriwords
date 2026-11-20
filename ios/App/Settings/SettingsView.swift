import SwiftUI
import ToriEnrichment
import ToriStore
import ToriSync
import ToriUI
import Translation

/// Settings root: a native grouped list.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    let store: ToriStore

    @State private var newWordsPerDay: Int?
    @State private var translation: LanguageAvailability.Status?
    @State private var editingTime = false

    var body: some View {
        @Bindable var settings = env.settings
        let reminder = env.reminderScheduler
        List {
            Section {
                DrillRow(title: Text("New words per day"), value: newWordsPerDay.map { Text(verbatim: "\($0)") }) {
                    router.push(.newWordsPerDay)
                }
            } header: { Text("Learning") }

            Section {
                Toggle(isOn: Binding(get: { reminder.isEnabled }, set: { on in Task { await reminder.setEnabled(on) } })) {
                    Text("Daily reminder")
                }
                if reminder.isEnabled {
                    Button { withAnimation { editingTime.toggle() } } label: {
                        LabeledContent { Text(reminderDate, style: .time) } label: { Text("Time").foregroundStyle(Palette.text) }
                    }
                    if editingTime {
                        DatePicker(selection: Binding(get: { reminderDate }, set: setReminderTime),
                                   displayedComponents: .hourAndMinute) { Text("Time") }
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                    }
                }
                if reminder.isEnabled && reminder.isDenied {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Notifications are off for ToriWords").font(Typography.secondary)
                        Button("Open iOS Settings ›", action: openAppSettings)
                    }
                }
            } header: { Text("Reminders") }

            Section {
                DrillRow(title: Text("Accent"), value: Text(AccentName.short(settings.accent))) { router.push(.accent) }
                Toggle(isOn: $settings.autoPlayOnReveal) { Text("Auto-play on reveal") }
            } header: { Text("Pronunciation") }

            Section {
                DrillRow(title: Text("Translation"), value: translation.map { Text(TranslationStatusText.short($0)) }) {
                    router.push(.translation)
                }
                DrillRow(title: Text("Language"), value: Text(verbatim: AppLanguage.currentName)) { router.push(.language) }
                DrillRow(title: Text("iCloud sync"), value: env.syncCoordinator.model.status.map(CloudSyncText.rowValue)) {
                    router.push(.cloudSync)
                }
                DrillRow(title: Text("Data"), value: nil) { router.push(.data) }
                DrillRow(title: Text("About"), value: nil) { router.push(.about) }
            }
        }
        .navigationTitle(Text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase == .active) {
            translation = await AppleTranslator.availability()
            await env.reminderScheduler.refresh()
            let values = store.observe { try $0.newWordsPerDay() }
            do { for try await n in values { newWordsPerDay = n } } catch {}
        }
    }

    private var reminderDate: Date {
        Calendar.current.date(bySettingHour: env.reminderScheduler.hour, minute: env.reminderScheduler.minute,
                              second: 0, of: Date()) ?? Date()
    }

    private func setReminderTime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        Task { await env.reminderScheduler.setTime(hour: parts.hour ?? 19, minute: parts.minute ?? 0) }
    }
}

@MainActor func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

/// A grouped-list row that pushes a drill-in: title, trailing value, chevron.
struct DrillRow: View {
    let title: Text
    let value: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                title.foregroundStyle(Palette.text)
                Spacer()
                if let value { value.foregroundStyle(Palette.textSecondary) }
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Palette.border)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: New words per day (11-1 SD1)

struct NewWordsPerDayView: View {
    let store: ToriStore
    @State private var value: Int?
    @State private var errorShown = false

    var body: some View {
        List {
            Section {
                if let value {
                    Stepper(value: Binding(get: { value }, set: save), in: ToriStore.newWordsPerDayRange) {
                        Text("\(value) new words a day")
                    }
                }
            } footer: {
                Text("Counts words, not cards: each new word brings its cards. Applies on all your devices.")
            }
        }
        .navigationTitle(Text("New words per day"))
        .navigationBarTitleDisplayMode(.inline)
        .task { value = try? store.read { try $0.newWordsPerDay() } }
        .alert(Text("Something went wrong"), isPresented: $errorShown) { Button("OK") {} }
    }

    private func save(_ n: Int) {
        value = n
        do { try store.setNewWordsPerDay(n) } catch { errorShown = true }
    }
}

// MARK: Accent (11-1 SD4)

enum AccentName {
    static func short(_ accent: Accent) -> LocalizedStringResource { accent == .us ? "US" : "UK" }
    static func long(_ accent: Accent) -> LocalizedStringResource { accent == .us ? "US English" : "UK English" }
}

struct AccentView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                ForEach(Accent.allCases, id: \.self) { accent in
                    Button { select(accent) } label: {
                        HStack {
                            Text(AccentName.long(accent)).foregroundStyle(Palette.text)
                            Spacer()
                            if env.settings.accent == accent {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(env.settings.accent == accent ? .isSelected : [])
                }
            } footer: {
                Text("Words are spoken with this iPhone's English voice. Applies to this device only.")
            }
        }
        .navigationTitle(Text("Accent"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ accent: Accent) {
        env.settings.accent = accent
        env.speech.accent = accent
    }
}

// MARK: Language (11-1 SD5): only the iOS per-app setting (UQ-12 closed).

enum AppLanguage {
    /// The language the UI is shown in, in that language ("English", "Русский").
    static var currentName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }
}

struct LanguageView: View {
    var body: some View {
        List {
            Section {
                LabeledContent { Text(verbatim: AppLanguage.currentName) } label: { Text("App language") }
                Button("Change in iOS Settings ›", action: openAppSettings)
            } footer: {
                Text("Changes the interface only. Your words, sentences and translations stay as they are.")
            }
        }
        .navigationTitle(Text("Language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
