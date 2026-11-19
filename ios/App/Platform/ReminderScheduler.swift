import Foundation
import Observation
import ToriCore
import ToriShared
import UserNotifications

/// The one optional daily reminder. Per device: on/off and time live in UserDefaults.
/// Settings (9c) binds to `isEnabled`, `hour`, `minute`, `isDenied` and calls `setEnabled` / `setTime`.
@MainActor @Observable
final class ReminderScheduler: NSObject, ReminderScheduling, UNUserNotificationCenterDelegate {
    private(set) var isEnabled: Bool
    private(set) var hour: Int
    private(set) var minute: Int
    /// "Notifications are off for ToriWords": the user turned the reminder on but the system denies it.
    private(set) var isDenied = false

    /// Today's snapshot (the App Group file just written, or computed from the store).
    @ObservationIgnored var snapshot: @MainActor () -> WidgetSnapshot? = { nil }
    /// Notification tap.
    @ObservationIgnored var open: @MainActor (URL) -> Void = { _ in }

    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private static let prefix = "reminder-"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "reminderEnabled")
        hour = defaults.object(forKey: "reminderHour") as? Int ?? 19
        minute = defaults.object(forKey: "reminderMinute") as? Int ?? 0
        super.init()
        // Before launch finishes, so a tap that cold-starts the app is delivered.
        center.delegate = self
    }

    func enableDailyReminder(hour: Int, minute: Int) async {
        setTimeValues(hour: hour, minute: minute)
        await setEnabled(true)
    }

    /// Permission is asked only here, when the user turns the reminder on; never again by itself.
    func setEnabled(_ on: Bool) async {
        isEnabled = on
        defaults.set(on, forKey: "reminderEnabled")
        if on {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            isDenied = !granted
        }
        await refresh()
    }

    func setTime(hour: Int, minute: Int) async {
        setTimeValues(hour: hour, minute: minute)
        await refresh()
    }

    /// Replaces the pending `reminder-<day>` requests with up to 7 from the current snapshot.
    func refresh() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled else { return }
        let settings = await center.notificationSettings()
        isDenied = settings.authorizationStatus == .denied
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              let snapshot = snapshot() else { return }
        let requests = ReminderPlan.requests(snapshot: snapshot, hour: hour, minute: minute, now: Now.ms,
                                             utcOffsetMin: Now.utcOffsetMin)
        for r in requests {
            let content = UNMutableNotificationContent()
            // N counts cards (reviews + new), as Home's Due today; hence not "words".
            content.body = String(localized: "\(r.count) to review")
            content.sound = .default
            content.userInfo = ["url": DeepLink.review.url.absoluteString]
            // Calendar components without a time zone: fires at the local time in whatever zone the device is in.
            let when = DateComponents(year: r.year, month: r.month, day: r.day, hour: r.hour, minute: r.minute)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.identifier, content: content, trigger: trigger))
        }
    }

    private func setTimeValues(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
        defaults.set(hour, forKey: "reminderHour")
        defaults.set(minute, forKey: "reminderMinute")
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let url = (response.notification.request.content.userInfo["url"] as? String).flatMap(URL.init(string:))
            ?? DeepLink.review.url
        await MainActor.run { open(url) }
    }

    /// The app is open: no banner, the user is already here.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [] }
}
