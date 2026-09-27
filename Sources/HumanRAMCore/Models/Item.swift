import Foundation

/// Tasks are executable memory; notes are volatile short-term memory that gets
/// flushed to the journal during the nightly review.
public enum ItemKind: String, Codable, CaseIterable {
    case task
    case note
}

public enum ItemState: String, Codable, CaseIterable {
    /// Task, in the working set — actively on your mind.
    case loaded
    /// Task, spilled to the "hard drive" — stored but not active.
    case backlog
    /// Task, completed — filed into the diary.
    case done
    /// Note, captured and waiting in the inbox.
    case inbox
    /// Note, filed into the journal.
    case journaled
}

public struct Item: Identifiable, Equatable {
    public var id: UUID = UUID()
    public var kind: ItemKind = .task
    public var text: String
    public var detail: String?
    public var dueAt: Date?
    /// When the task should enter RAM. Falls back to `dueAt` for activation.
    public var startAt: Date?
    public var state: ItemState = .loaded
    /// Tasks only: 0 = none, 1 = low, 2 = normal, 3 = high. Notes always keep 0.
    public var priority: Int = 2
    public var createdAt: Date = Date()
    /// When it entered the working set (drives decay).
    public var loadedAt: Date? = Date()
    /// Last meaningful touch (edit / surface), drives decay too.
    public var touchedAt: Date = Date()
    /// Task completion time, or note journaling time.
    public var completedAt: Date?
    /// Pinned items are never auto-spilled.
    public var pinned: Bool = false
    /// Last local mutation time; synced and used for last-writer-wins.
    public var updatedAt: Date = Date()
    /// Tombstone: row is kept so deletions propagate across devices.
    public var deleted: Bool = false
    /// True when the row has local changes that still need to be pushed.
    public var dirty: Bool = true

    public init(
        id: UUID = UUID(),
        kind: ItemKind = .task,
        text: String,
        detail: String? = nil,
        dueAt: Date? = nil,
        startAt: Date? = nil,
        state: ItemState = .loaded,
        priority: Int = 2,
        createdAt: Date = Date(),
        loadedAt: Date? = Date(),
        touchedAt: Date = Date(),
        completedAt: Date? = nil,
        pinned: Bool = false,
        updatedAt: Date = Date(),
        deleted: Bool = false,
        dirty: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
        self.dueAt = dueAt
        self.startAt = startAt
        self.state = state
        self.priority = priority
        self.createdAt = createdAt
        self.loadedAt = loadedAt
        self.touchedAt = touchedAt
        self.completedAt = completedAt
        self.pinned = pinned
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.dirty = dirty
    }

    public var isNote: Bool { kind == .note }

    /// The moment a task becomes relevant to RAM: its start, else its due date.
    public var activationAt: Date? { startAt ?? dueAt }

    /// True when the task has a start time still in the future.
    public var hasUpcomingStart: Bool {
        guard let startAt else { return false }
        return startAt > Date()
    }

    public var isDue: Bool {
        guard let dueAt else { return false }
        return dueAt <= Date()
    }

    /// 0…1 freshness since it was last touched, used to dim stale items.
    /// Editing or re-loading a task refreshes it; decay is only about neglect.
    public func freshness(decayDimDays: Int, now: Date = Date()) -> Double {
        guard state == .loaded else { return 1 }
        let days = now.timeIntervalSince(touchedAt) / 86_400
        guard decayDimDays > 0 else { return 1 }
        return max(0, min(1, 1 - days / Double(decayDimDays)))
    }
}
