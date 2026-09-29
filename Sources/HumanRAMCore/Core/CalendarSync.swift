import Foundation
import Combine
import EventKit

/// Mirrors tasks with times into a calendar, one-way (app → calendar). Because
/// the Mac's Calendar app aggregates iCloud/Google/Exchange accounts, those
/// events (and their alarms) reach the user's phone without any server.
///
/// One-way: edits made in Calendar are ignored. Each task remembers its event
/// id so updates and deletions stay in sync.
public final class CalendarSync {
    public static let shared = CalendarSync()
    public static let dedicatedCalendarTitle = "Human RAM"

    public struct CalendarOption: Identifiable, Hashable {
        public let id: String
        public let title: String
        public let source: String

        public var displayName: String { source.isEmpty ? title : "\(title) (\(source))" }
    }

    public enum Permission {
        case notDetermined
        case denied
        case authorized
    }

    private let store = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    private weak var itemStore: ItemStore?
    private var pending: DispatchWorkItem?

    private init() {}

    /// Subscribes to item and setting changes and performs an initial sync.
    public func start(itemStore: ItemStore, settings: AppSettings = .shared) {
        self.itemStore = itemStore

        itemStore.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.schedule() }
            .store(in: &cancellables)

        settings.$calendarSyncEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.schedule() }
            .store(in: &cancellables)

        settings.$calendarIdentifier
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.schedule() }
            .store(in: &cancellables)

        if settings.calendarSyncEnabled {
            requestAccess { [weak self] _ in self?.schedule() }
        }
    }

    // MARK: - Permission

    public func permission() -> Permission {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    public func requestAccess(_ completion: ((Bool) -> Void)? = nil) {
        store.requestFullAccessToEvents { granted, error in
            if let error { NSLog("Human RAM calendar access error: \(error.localizedDescription)") }
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    /// Writable calendars the user can target, for the Settings picker.
    public func availableCalendars() -> [CalendarOption] {
        guard permission() == .authorized else { return [] }
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { CalendarOption(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "") }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Sync

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncNow() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Reconciles every timed task with its calendar event. Safe to call often.
    public func syncNow() {
        guard let itemStore else { return }
        guard AppSettings.shared.calendarSyncEnabled else {
            removeTrackedEvents(from: itemStore)
            return
        }
        guard permission() == .authorized, let calendar = targetCalendar() else { return }

        let eligible = itemStore.items.filter {
            !$0.deleted && $0.kind == .task && $0.state != .done && ($0.dueAt != nil || $0.startAt != nil)
        }

        var kept = Set<String>()
        for item in eligible {
            if let eventID = item.calendarEventId, let event = store.event(withIdentifier: eventID) {
                apply(item, to: event, calendar: calendar)
                save(event)
                kept.insert(eventID)
            } else {
                let event = EKEvent(eventStore: store)
                apply(item, to: event, calendar: calendar)
                if save(event), let id = event.eventIdentifier {
                    itemStore.setCalendarEventId(id, for: item.id)
                    kept.insert(id)
                }
            }
        }

        // Remove events for tasks that no longer qualify (done, deleted, undated).
        for item in itemStore.items {
            guard let eventID = item.calendarEventId, !kept.contains(eventID) else { continue }
            if let event = store.event(withIdentifier: eventID) {
                try? store.remove(event, span: .thisEvent)
            }
            itemStore.setCalendarEventId(nil, for: item.id)
        }
    }

    private func apply(_ item: Item, to event: EKEvent, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = item.text
        event.notes = item.detail
        event.isAllDay = false

        let start = item.startAt
        let due = item.dueAt
        if let start, let due, due > start {
            event.startDate = start
            event.endDate = due
        } else if let due {
            event.startDate = due.addingTimeInterval(-1800)
            event.endDate = due
        } else if let start {
            event.startDate = start
            event.endDate = start.addingTimeInterval(1800)
        }

        event.alarms = []
        if let anchor = due ?? start {
            event.addAlarm(EKAlarm(absoluteDate: anchor))
        }
    }

    @discardableResult
    private func save(_ event: EKEvent) -> Bool {
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            NSLog("Human RAM calendar save failed: \(error.localizedDescription)")
            return false
        }
    }

    private func removeTrackedEvents(from itemStore: ItemStore) {
        guard permission() == .authorized else { return }
        for item in itemStore.items {
            guard let eventID = item.calendarEventId else { continue }
            if let event = store.event(withIdentifier: eventID) {
                try? store.remove(event, span: .thisEvent)
            }
            itemStore.setCalendarEventId(nil, for: item.id)
        }
    }

    private func targetCalendar() -> EKCalendar? {
        let chosen = AppSettings.shared.calendarIdentifier
        if !chosen.isEmpty, let calendar = store.calendar(withIdentifier: chosen) {
            return calendar
        }
        if let existing = store.calendars(for: .event)
            .first(where: { $0.title == Self.dedicatedCalendarTitle && $0.allowsContentModifications }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.dedicatedCalendarTitle
        calendar.source = preferredSource()
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            NSLog("Human RAM calendar create failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func preferredSource() -> EKSource? {
        if let source = store.defaultCalendarForNewEvents?.source { return source }
        return store.sources.first { $0.sourceType == .local } ?? store.sources.first
    }
}
