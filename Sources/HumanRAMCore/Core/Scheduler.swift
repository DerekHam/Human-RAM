import Foundation
import Combine

/// Drives time-based behaviour: reminders, decay, the daily scan, and the
/// nightly note review.
public final class Scheduler {
    public static let shared = Scheduler()

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var started = false

    /// Backed by UserDefaults so each fires at most once per day,
    /// even across relaunches.
    private var lastScanDay: Date? {
        get { UserDefaults.standard.object(forKey: "lastScanDay") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastScanDay") }
    }

    private var lastNoteReviewDay: Date? {
        get { UserDefaults.standard.object(forKey: "lastNoteReviewDay") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastNoteReviewDay") }
    }

    public func start(store: ItemStore) {
        guard !started else { return }
        started = true

        Notifications.shared.configure()
        scheduleDailyDigest()
        scheduleNoteReview(store: store)

        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                Notifications.shared.syncDueNotifications(items: items)
                self?.scheduleNoteReview(store: store)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .humanRAMScheduleChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Re-schedule the notifications, but keep the once-per-day
                // bookkeeping: a settings tweak should not re-run today's scan.
                self?.scheduleDailyDigest()
                self?.scheduleNoteReview(store: store)
            }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick(store: store)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Housekeeping on launch.
        store.applyDecay()
        store.applyTimeWindow()
        tick(store: store, isLaunch: true)
    }

    private func scheduleDailyDigest() {
        let s = AppSettings.shared
        Notifications.shared.scheduleDailyDigest(hour: s.dailyScanHour, minute: s.dailyScanMinute)
    }

    private func scheduleNoteReview(store: ItemStore) {
        let s = AppSettings.shared
        // Only remind when there is something to review, so an empty inbox
        // never gets a nightly "thoughts are waiting" alert.
        Notifications.shared.scheduleNoteReview(
            hour: s.noteReviewHour,
            minute: s.noteReviewMinute,
            enabled: s.noteReviewEnabled && !store.notesInbox.isEmpty
        )
    }

    private func tick(store: ItemStore, isLaunch: Bool = false) {
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        store.applyTimeWindow()

        if lastScanDay != today, now >= timeToday(AppSettings.shared.dailyScanHour, AppSettings.shared.dailyScanMinute, now: now) {
            lastScanDay = today
            runDailyScan(store: store)
        }

        if AppSettings.shared.noteReviewEnabled,
           lastNoteReviewDay != today,
           now >= timeToday(AppSettings.shared.noteReviewHour, AppSettings.shared.noteReviewMinute, now: now) {
            // Mark the day handled either way so a launch-time catch-up is not
            // re-run by the next timer tick.
            lastNoteReviewDay = today
            if !isLaunch || AppSettings.shared.noteReviewOnLaunch {
                runNoteReview(store: store)
            }
        }
    }

    private func timeToday(_ hour: Int, _ minute: Int, now: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps) ?? now
    }

    private func runDailyScan(store: ItemStore) {
        store.applyDecay()
        store.applyTimeWindow()
        DispatchQueue.main.async {
            AppRouter.shared.presentDailyScan()
        }
    }

    private func runNoteReview(store: ItemStore) {
        // Only pull up the window if there's actually something to review.
        guard !store.notesInbox.isEmpty else { return }
        DispatchQueue.main.async {
            AppRouter.shared.presentNotesReview()
        }
    }
}