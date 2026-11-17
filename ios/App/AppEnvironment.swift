import BackgroundTasks
import Foundation
import Observation
import ToriCore
import ToriDictionary
import ToriEnrichment
import ToriShared
import ToriStore
import UIKit
import WidgetKit

/// Slot for ToriSync (wired in a later step): token purge on a fresh install, launch reconciliation, sync triggers.
@MainActor protocol SyncCoordinating: AnyObject {
    /// Fresh install: delete Session tokens left in the Keychain by a previous installation (§4.7).
    func purgeLeftoverTokens()
    /// §4.7 step 5 / §12.5: launch reconciliation and a sync when signed in.
    func syncIfSignedIn() async
    /// Scene went to the background (ends the foreground for the session check, §12.3).
    func didEnterBackground() async
    /// BG app refresh: one cycle if signed in and not paused (§10.4).
    func backgroundRefresh() async
}

extension SyncCoordinating {
    func didEnterBackground() async {}
    func backgroundRefresh() async {}
}

/// Slot for the dictionary step: copy the bundled `dictionary.sqlite` into the App Group when its version changed
/// (§8.3) and open it. Returns nil when no dictionary is available.
@MainActor protocol DictionaryInstalling: AnyObject {
    func installIfNeeded(into group: AppGroup?) async throws -> (any DictionaryLookup)?
}

/// Slot for reminders (step 9d). The Review reminder offer calls `enableDailyReminder`; commits call `refresh`.
@MainActor protocol ReminderScheduling: AnyObject {
    func enableDailyReminder(hour: Int, minute: Int) async
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accent = defaults.string(forKey: "accent").flatMap(Accent.init(rawValue:)) ?? .us
        autoPlayOnReveal = defaults.bool(forKey: "autoPlayOnReveal")
        swipeDemoShown = defaults.bool(forKey: "swipeDemoShown")
        reminderOfferShown = defaults.bool(forKey: "reminderOfferShown")
    }
}

/// Composition root: owns the services and runs the launch sequence (§4.7) before any data is shown.
@MainActor @Observable
final class AppEnvironment {
    enum Phase: Equatable { case launching, ready, failed(String) }

    private(set) var phase: Phase = .launching
    private(set) var store: ToriStore?
    private(set) var enrichment: EnrichmentOrchestrator?
    let router = Router()
    let settings = DeviceSettings()
    let speech: SpeechPlayer
    let translationBridge = TranslationBridge()
    let appGroup = AppGroup.shared
    let deletion = PendingDeletion()

    // Slots wired by later steps.
    @ObservationIgnored var sync: (any SyncCoordinating)?
    @ObservationIgnored var dictionaryInstaller: (any DictionaryInstalling)? = AppDictionaryInstaller()
    /// The installed dictionary (search, autocomplete); nil until launch installed it or when none is bundled.
    var dictionary: BundledDictionary? { (dictionaryInstaller as? AppDictionaryInstaller)?.dictionary }
    @ObservationIgnored var reminders: (any ReminderScheduling)?
    /// Dictionary searches for Add / Entry over `dictionary` (set by the installer at launch); empty while it is nil.
    var dictionarySearch: DictionarySearch { DictionarySearch(dictionary) }

    /// The open Review session, so going to the background commits its undoable answer (§7.8).
    @ObservationIgnored weak var activeReview: ReviewModel?
    @ObservationIgnored private var appGroupRefresh: Task<Void, Never>?
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var vocabularyObserver: Task<Void, Never>?
    @ObservationIgnored private var inboxObserver: InboxNotification.Observer?

    /// Concrete services behind the slots, for the Account and Settings screens (9c).
    let syncCoordinator = SyncCoordinator()
    let reminderScheduler = ReminderScheduler()

    init() {
        speech = SpeechPlayer(accent: settings.accent)
        sync = syncCoordinator
        reminders = reminderScheduler
        reminderScheduler.open = { [weak self] url in self?.open(url) }
        reminderScheduler.snapshot = { [weak self] in self?.currentSnapshot() }
    }

    // MARK: Launch (§4.7)

    /// Idempotent: the scene's `.task` and a background refresh launch may both call it.
    func launch() async {
        if launchTask == nil { launchTask = Task { await performLaunch() } }
        await launchTask?.value
    }

    private func performLaunch() async {
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
            let dictionary = try? await dictionaryInstaller?.installIfNeeded(into: appGroup)
            // 5: inbox import, then pending enrichment, then sync.
            if let appGroup { _ = try? store.importInbox(appGroup.inbox) }
            syncCoordinator.attach(store: store)
            let enrichment = EnrichmentOrchestrator(store: store, dictionary: dictionary,
                                                    translator: AppleTranslator(bridge: translationBridge))
            self.store = store
            self.enrichment = enrichment
            deletion.store = store
            deletion.didDelete = { [weak self] in self?.didChangeWords() }
            phase = .ready
            observe(store)
            let dictionaryChanged = (dictionaryInstaller as? AppDictionaryInstaller)?.versionChanged == true
            Task {
                // §8.3: after a version change `unavailable` Entries get another chance (also runs pending).
                if dictionaryChanged { _ = try? await enrichment.updateDictionary(dictionary) }
                else { _ = try? await enrichment.runPending() }
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

    /// Snapshot + vocab index after any vocabulary change, including sync applies (§10.1); inbox import on the
    /// Share Extension's Darwin notification while running (§5.6).
    private func observe(_ store: ToriStore) {
        vocabularyObserver = Task { [weak self] in
            for await _ in store.vocabularyChanges() { self?.scheduleAppGroupRefresh(delay: .seconds(2)) }
        }
        inboxObserver = InboxNotification.Observer { [weak self] in Task { @MainActor in self?.importInbox() } }
    }

    private func importInbox() {
        guard let store, let enrichment, let appGroup,
              let result = try? store.importInbox(appGroup.inbox), !result.imported.isEmpty else { return }
        Task { _ = try? await enrichment.runPending() }
    }

    // MARK: Deep links (§10.2, §10.3)

    /// `toriwords://review` (widget, reminder) and `toriwords://add?text=…`.
    func open(_ url: URL) {
        switch DeepLink(url: url) {
        case .review:
            router.openReview()
        case .add(let text):
            if router.isReviewPresented {
                activeReview?.commitPending()
                router.isReviewPresented = false
            }
            router.push(.add(text: text))
        case nil:
            break
        }
    }

    // MARK: Background refresh (§10.4)

    /// `BGAppRefreshTask`: inbox → sync → enrichment → snapshot + widget → reminders. Cancellation (expiration) stops
    /// between steps; every step is safe to cut short.
    func backgroundRefresh() async {
        await launch()
        guard phase == .ready else { return }
        importInbox()
        guard !Task.isCancelled else { return }
        await sync?.backgroundRefresh()
        guard !Task.isCancelled else { return }
        _ = try? await enrichment?.runPending()
        guard !Task.isCancelled else { return }
        appGroupRefresh?.cancel()
        writeAppGroupFiles()
        await reminders?.refresh()
        scheduleBackgroundRefresh()
    }

    /// Requested on every background transition, earliest in about 4 hours.
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Background: commit the undoable answer, flush the App Group files, checkpoint the WAL (§3, §7.8).
    func didEnterBackground() {
        activeReview?.commitPending()
        deletion.commit()
        translationBridge.cancelAll()
        speech.stop()
        appGroupRefresh?.cancel()
        writeAppGroupFiles()
        Task { await reminders?.refresh() }
        try? store?.checkpoint()
        scheduleBackgroundRefresh()
        Task { await sync?.didEnterBackground() }
    }

    // MARK: After a write

    /// After a review commit: debounced snapshot + vocab index (§7.8, 2 s) and reminders.
    func didCommitAnswer() {
        scheduleAppGroupRefresh(delay: .seconds(2))
    }

    /// Speaks with the per-device accent (§9).
    func speak(_ text: String, _ trigger: SpeechPlayer.Trigger) {
        speech.accent = settings.accent
        speech.speak(text, trigger: trigger)
    }

    /// After an add, edit, status change or delete: the widget snapshot and the Share Extension's vocab index follow.
    func didChangeWords() {
        scheduleAppGroupRefresh(delay: .seconds(2))
        Task { await reminders?.refresh() }
    }

    private func scheduleAppGroupRefresh(delay: Duration) {
        appGroupRefresh?.cancel()
        appGroupRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeAppGroupFiles()
            await self?.reminders?.refresh()
        }
    }

    private func writeAppGroupFiles() {
        guard let store, let appGroup else { return }
        try? store.writeAppGroupFiles(appGroup, now: Now.ms, utcOffsetMin: Now.utcOffsetMin)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// For reminders: computed now, so a stale App Group file (or none, without the entitlement) never matters.
    private func currentSnapshot() -> WidgetSnapshot? {
        try? store?.read { try $0.widgetSnapshot(now: Now.ms, utcOffsetMin: Now.utcOffsetMin) }
    }
}
