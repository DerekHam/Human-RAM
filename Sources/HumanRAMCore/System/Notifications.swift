import Foundation
import UserNotifications

/// Wraps local notifications for due items and the daily digest.
public final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = Notifications()

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        requestAuthorization()
    }

    /// Asks for permission (no-op if the user already decided). macOS only shows
    /// the prompt while the app is launched normally, not from a bare binary.
    public func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { NSLog("HumanRAM notification auth error: \(error.localizedDescription)") }
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    /// Current permission, delivered on the main thread.
    public func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    /// Fires a local notification a few seconds out, so the user can confirm
    /// permission and Do Not Disturb are actually set up.
    public func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Human RAM"
        content.body = "Notifications are working."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    /// Re-sync scheduled reminders so they mirror the current due items.
    func syncDueNotifications(items: [Item]) {
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            let dueIDs = pending.map(\.identifier).filter { $0.hasPrefix("due-") }
            self.center.removePendingNotificationRequests(withIdentifiers: dueIDs)

            let now = Date()
            for item in items where item.kind == .task && !item.deleted && item.state != .done {
                guard let due = item.dueAt, due > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Time for: \(item.text)"
                content.body = item.detail ?? "From your Human RAM"
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "due-\(item.id.uuidString)",
                    content: content,
                    trigger: trigger
                )
                self.center.add(request)
            }
        }
    }

    func scheduleDailyDigest(hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-digest"])
        let content = UNMutableNotificationContent()
        content.title = "Daily Scan"
        content.body = "Here's what's on your mind today."
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "daily-digest", content: content, trigger: trigger))
    }

    func scheduleNoteReview(hour: Int, minute: Int, enabled: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: ["notes-review"])
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tonight's Notes"
        content.body = "A few thoughts are waiting. Review them before bed."
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "notes-review", content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            if id == "notes-review" {
                AppRouter.shared.presentNotesReview()
            } else if id == "daily-digest" || id.hasPrefix("due-") {
                AppRouter.shared.presentDailyScan()
            }
            completionHandler()
        }
    }
}