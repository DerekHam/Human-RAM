import Foundation
import UserNotifications

/// Wraps local notifications for due items and the daily digest.
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { NSLog("HumanRAM notification auth error: \(error.localizedDescription)") }
            _ = granted
        }
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
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
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
        }
        completionHandler()
    }
}