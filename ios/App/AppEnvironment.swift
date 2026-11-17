import Foundation
import Observation
import ToriCore
import ToriEnrichment
import ToriShared
import ToriStore
import ToriSync
import UIKit

/// Slot for ToriSync (wired in a later step): token purge on a fresh install, launch reconciliation, sync triggers.
@MainActor protocol SyncCoordinating: AnyObject {
    /// Fresh install: delete Session tokens left in the Keychain by a previous installation (§4.7).
    func purgeLeftoverTokens()
    /// §4.7 step 5 / §12.5: launch reconciliation and a sync when signed in.
    func syncIfSignedIn() async

    // Settings → Account (doc 35 §3.10, doc 36 §11.10, §12). Observable: the Account screen reads `status` in its body.
    var status: SyncStatus { get }
    /// Runs the provider's sign-in UI (Apple: ASAuthorization; Google: web auth session), then `SyncEngine.signIn`.
    /// Throws when the user cancels or the server refuses; the Account screen shows a generic error except on cancel.
    func signIn(with provider: SignInProvider) async throws
    /// "Sync now".
    func syncNow() async
    /// "Add these N words to this account" / "Remove all N words from this device" (§12.5). Cancel needs no call.
    func resolveAccountChoice(_ choice: AccountChoice) async -> ChoiceResult
    func signOut() async throws
    /// Needs a connection; throws `APIError` otherwise.
    func deleteAccount(removeLocalData: Bool) async throws
    /// Drops `status.notices.first` after the Account screen showed it.
    func dismissNotice()
}

enum SignInProvider: String, Sendable {
    /// Raw values are the `lastProvider` sync_state values.
    case apple, google
}

/// What About and Translation show from the bundled dictionary (doc 36 §8.4): `meta.dictionary_version` and
/// `meta.licence_text`. The dictionary step makes its `BundledDictionary` conform.
protocol DictionaryAttribution {
    var version: String { get }
    var licenceText: String { get }
}

/// Slot for the dictionary step: copy the bundled `dictionary.sqlite` into the App Group when its version changed
/// (§8.3) and open it. Returns nil when no dictionary is available.
@MainActor protocol DictionaryInstalling: AnyObject {
    func installIfNeeded(into group: AppGroup?) throws -> (any DictionaryLookup)?
}

/// Slot for reminders (step 9d). The Review reminder offer and Settings call `enableDailyReminder`; commits call `refresh`.
/// The implementation owns `DeviceSettings.reminderEnabled / reminderHour / reminderMinute`: it sets them when the
/// reminder is turned on (permission granted) or its time changes, and clears `reminderEnabled` on disable.
@MainActor protocol ReminderScheduling: AnyObject {
    func enableDailyReminder(hour: Int, minute: Int) async
    func disableDailyReminder() async
    /// Settings shows "Notifications are off for ToriWords" when true (SD3); the app never asks again by itself.
    func notificationsDenied() async -> Bool
    func refresh() async
}

/// Wall clock in the units the store uses.
enum Now {
    static var ms: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    static var utcOffsetMin: Int { TimeZone.current.secondsFromGMT(for: Date()) / 60 }
    static var today: Int { DayModel.dayNumber(unixMs: ms, utcOffsetMin: utcOffsetMin) }
}

/// Per-device settings in `UserDefaults` (§3, §4.5).
@MainActor @Observable
final class DeviceSettings {
    private let defaults: UserDefaults

    var accent: Accent { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    var autoPlayOnReveal: Bool { didSet { defaults.set(autoPlayOnReveal, forKey: "autoPlayOnReveal") } }
    var swipeDemoShown: Bool { didSet { defaults.set(swipeDemoShown, forKey: "swipeDemoShown") } }
    var reminderOfferShown: Bool { didSet { defaults.set(reminderOfferShown, forKey: "reminderOfferShown") } }
    /// Written by `ReminderScheduling` only (default off, 19:00).
    var reminderEnabled: Bool { didSet { defaults.set(reminderEnabled, forKey: "reminderEnabled") } }
    var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: "reminderHour") } }
    var reminderMinute: Int { didSet { defaults.set(reminderMinute, forKey: "reminderMinute") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accent = defaults.string(forKey: "accent").flatMap(Accent.init(rawValue:)) ?? .us
        autoPlayOnReveal = defaults.bool(forKey: "autoPlayOnReveal")
        swipeDemoShown = defaults.bool(forKey: "swipeDemoShown")
        reminderOfferShown = defaults.bool(forKey: "reminderOfferShown")
        reminderEnabled = defaults.bool(forKey: "reminderEnabled")
        reminderHour = defaults.object(forKey: "reminderHour") as? Int ?? 19
        reminderMinute = defaults.integer(forKey: "reminderMinute")
    }
}

/// Composition root: owns the services and runs the launch sequence (§4.7) before any data is shown.
@MainActor @Observable
final class AppEnvironment {
    enum Phase: Equatable { case launching, ready, failed(String) }

    private(set) var phase: Phase = .launching
    private(set) var store: ToriStore?
    private(set) var enrichment: EnrichmentOrchestrator?
    /// The installed dictionary; About and Translation read its version and licence (`DictionaryAttribution`).
    private(set) var dictionary: (any DictionaryLookup)?
    let router = Router()
    let settings = DeviceSettings()
    let speech: SpeechPlayer
    let translationBridge = TranslationBridge()
    let appGroup = AppGroup.shared

    // Slots wired by later steps.
    @ObservationIgnored var sync: (any SyncCoordinating)?
    @ObservationIgnored var dictionaryInstaller: (any DictionaryInstalling)?
    @ObservationIgnored var reminders: (any ReminderScheduling)?

    /// The open Review session, so going to the background commits its undoable answer (§7.8).
    @ObservationIgnored weak var activeReview: ReviewModel?
    @ObservationIgnored private var appGroupRefresh: Task<Void, Never>?

    init() {
        speech = SpeechPlayer(accent: settings.accent)
    }

    // MARK: Launch (§4.7)

    func launch() async {
        guard phase != .ready else { return }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            let deviceName = UIDevice.current.model
            // 1–3: open/migrate, then fresh install / restore detection. Off the main actor: may migrate.
            let (store, outcome) = try await Task.detached {
                let store = try ToriStore(path: support.appending(path: "user.sqlite").path)
                let outcome = try store.launch(deviceMarker: support.appending(path: "device-marker"),
                                               displayName: deviceName, purgeKeychain: {})
                return (store, outcome)
            }.value
            if outcome == .freshInstall { sync?.purgeLeftoverTokens() }
            // 4: dictionary into the App Group.
            let dictionary = try? dictionaryInstaller?.installIfNeeded(into: appGroup)
            // 5: inbox import, then pending enrichment, then sync.
            if let appGroup { _ = try? store.importInbox(appGroup.inbox) }
            self.dictionary = dictionary
            let enrichment = EnrichmentOrchestrator(store: store, dictionary: dictionary,
                                                    translator: AppleTranslator(bridge: translationBridge))
            self.store = store
            self.enrichment = enrichment
            phase = .ready
            Task {
                _ = try? await enrichment.runPending()
                await sync?.syncIfSignedIn()
            }
            scheduleAppGroupRefresh(delay: .zero)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    // MARK: Scene phase

    func didBecomeActive() {
        guard let store, let enrichment else { return }
        if let appGroup { _ = try? store.importInbox(appGroup.inbox) }
        Task {
            _ = try? await enrichment.runPending()
            await sync?.syncIfSignedIn()
        }
    }

    /// Background: commit the undoable answer, flush the App Group files, checkpoint the WAL (§3, §7.8).
    func didEnterBackground() {
        activeReview?.commitPending()
        translationBridge.cancelAll()
        speech.stop()
        appGroupRefresh?.cancel()
        writeAppGroupFiles()
        try? store?.checkpoint()
    }

    // MARK: After a write

    /// After a review commit: debounced snapshot + vocab index (§7.8, 2 s) and reminders.
    func didCommitAnswer() { didChangeData() }

    /// After any bulk write (restore, remove all data): same refresh as after an answer.
    func didChangeData() {
        scheduleAppGroupRefresh(delay: .seconds(2))
        Task { await reminders?.refresh() }
    }

    private func scheduleAppGroupRefresh(delay: Duration) {
        appGroupRefresh?.cancel()
        appGroupRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeAppGroupFiles()
        }
    }

    private func writeAppGroupFiles() {
        guard let store, let appGroup else { return }
        try? store.writeAppGroupFiles(appGroup, now: Now.ms, utcOffsetMin: Now.utcOffsetMin)
    }
}
