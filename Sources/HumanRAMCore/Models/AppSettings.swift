import Foundation
import Combine

/// User preferences, persisted in UserDefaults.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published public var workingSetLimit: Int { didSet { defaults.set(workingSetLimit, forKey: "workingSetLimit") } }
    /// Automatically spill/load tasks around the RAM time window.
    @Published public var autoArrangeEnabled: Bool { didSet { defaults.set(autoArrangeEnabled, forKey: "autoArrangeEnabled") } }
    /// How many hours ahead a task's start (or due) keeps it in RAM.
    @Published public var ramWindowHours: Int { didSet { defaults.set(ramWindowHours, forKey: "ramWindowHours") } }
    @Published public var decayDimDays: Int { didSet { defaults.set(decayDimDays, forKey: "decayDimDays") } }
    @Published public var decaySpillDays: Int { didSet { defaults.set(decaySpillDays, forKey: "decaySpillDays") } }
    @Published public var dailyScanHour: Int { didSet { defaults.set(dailyScanHour, forKey: "dailyScanHour") } }
    @Published public var dailyScanMinute: Int { didSet { defaults.set(dailyScanMinute, forKey: "dailyScanMinute") } }
    /// Carbon key code for the global capture hotkey (default: N = 45).
    @Published public var hotkeyKeyCode: Int { didSet { defaults.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") } }
    /// Carbon modifier flags (default: ⌘⇧ = cmdKey|shiftKey).
    @Published public var hotkeyModifiers: Int { didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }
    /// Year used by the DateTimeField; only touched by explicit edits.
    @Published public var year: Int { didSet { defaults.set(year, forKey: "year") } }
    @Published public var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published public var showGuideOnLaunch: Bool { didSet { defaults.set(showGuideOnLaunch, forKey: "showGuideOnLaunch") } }

    // Notes
    @Published public var noteCapacity: Int { didSet { defaults.set(noteCapacity, forKey: "noteCapacity") } }
    @Published public var noteReviewEnabled: Bool { didSet { defaults.set(noteReviewEnabled, forKey: "noteReviewEnabled") } }
    /// Open the review window on launch when the scheduled time already passed.
    /// Off means the review only appears at its time (or via notification/Review).
    @Published public var noteReviewOnLaunch: Bool { didSet { defaults.set(noteReviewOnLaunch, forKey: "noteReviewOnLaunch") } }
    @Published public var noteReviewHour: Int { didSet { defaults.set(noteReviewHour, forKey: "noteReviewHour") } }
    @Published public var noteReviewMinute: Int { didSet { defaults.set(noteReviewMinute, forKey: "noteReviewMinute") } }

    private init() {
        defaults.register(defaults: [
            "workingSetLimit": 7,
            "autoArrangeEnabled": true,
            "ramWindowHours": 48,
            "decayDimDays": 3,
            "decaySpillDays": 10,
            "dailyScanHour": 19,
            "dailyScanMinute": 20,
            "hotkeyKeyCode": 45,
            "hotkeyModifiers": 0x100 | 0x200,
            "year": Calendar.current.component(.year, from: Date()),
            "launchAtLogin": false,
            "showGuideOnLaunch": AppVariant.showsGuideByDefault,
            "noteCapacity": 15,
            "noteReviewEnabled": true,
            "noteReviewOnLaunch": false,
            "noteReviewHour": 0,
            "noteReviewMinute": 0,
        ])
        workingSetLimit = defaults.integer(forKey: "workingSetLimit")
        autoArrangeEnabled = defaults.bool(forKey: "autoArrangeEnabled")
        ramWindowHours = defaults.integer(forKey: "ramWindowHours")
        decayDimDays = defaults.integer(forKey: "decayDimDays")
        decaySpillDays = defaults.integer(forKey: "decaySpillDays")
        dailyScanHour = defaults.integer(forKey: "dailyScanHour")
        dailyScanMinute = defaults.integer(forKey: "dailyScanMinute")
        hotkeyKeyCode = defaults.integer(forKey: "hotkeyKeyCode")
        hotkeyModifiers = defaults.integer(forKey: "hotkeyModifiers")
        // The entry year is a session default: typed dates should mean the
        // upcoming occurrence as of now. A year left over from a previous
        // session (or a stale/rolled value) must not silently shift every date.
        let currentYear = Calendar.current.component(.year, from: Date())
        let storedYear = defaults.integer(forKey: "year")
        if storedYear == currentYear {
            year = storedYear
        } else {
            year = currentYear
            defaults.set(currentYear, forKey: "year")
        }
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        showGuideOnLaunch = defaults.bool(forKey: "showGuideOnLaunch")
        noteCapacity = defaults.integer(forKey: "noteCapacity")
        noteReviewEnabled = defaults.bool(forKey: "noteReviewEnabled")
        noteReviewOnLaunch = defaults.bool(forKey: "noteReviewOnLaunch")
        noteReviewHour = defaults.integer(forKey: "noteReviewHour")
        noteReviewMinute = defaults.integer(forKey: "noteReviewMinute")
    }

    public var dailyScanTime: DateComponents {
        DateComponents(hour: dailyScanHour, minute: dailyScanMinute, second: 0)
    }

    /// Next occurrence of the daily scan time.
    public func nextScanDate(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = dailyScanHour
        comps.minute = dailyScanMinute
        comps.second = 0
        let today = cal.date(from: comps) ?? now
        if today > now { return today }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Next occurrence of the nightly note-review time.
    public func nextNoteReviewDate(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = noteReviewHour
        comps.minute = noteReviewMinute
        comps.second = 0
        let today = cal.date(from: comps) ?? now
        if today > now { return today }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
