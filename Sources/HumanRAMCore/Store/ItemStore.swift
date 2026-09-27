import Foundation
import Combine
import WidgetKit
import HumanRAMShared

/// In-memory working copy of all items, write-through to SQLite.
public final class ItemStore: ObservableObject {
    public static let shared = ItemStore()

    /// Every row, including tombstones (`deleted == true`). UI queries filter deleted rows;
    /// tombstones are kept so removals can propagate during sync.
    @Published public private(set) var items: [Item] = []
    private let db: Database
    private let sharesWithWidget: Bool
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let path: String
        if let override = ProcessInfo.processInfo.environment["HRAM_DB_PATH"] {
            path = override
            sharesWithWidget = false
        } else {
            sharesWithWidget = !AppVariant.isShareable
            let fm = FileManager.default
            let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppVariant.storageFolderName, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("humanram.sqlite3").path
        }
        db = Database(path: path)
        migrate()
        reload()
        $items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.publishWidgetSnapshot() }
            .store(in: &cancellables)
    }

    private func publishWidgetSnapshot() {
        guard sharesWithWidget else { return }
        let tasks = loaded.map {
            WidgetTask(id: $0.id, text: $0.text, dueAt: $0.dueAt, priority: $0.priority, pinned: $0.pinned)
        }
        WidgetSnapshotStore.save(WidgetSnapshot(updatedAt: Date(), tasks: tasks))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Schema

    private func migrate() {
        db.exec("""
        CREATE TABLE IF NOT EXISTS items (
            id           TEXT PRIMARY KEY,
            kind         TEXT NOT NULL DEFAULT 'task',
            text         TEXT NOT NULL,
            detail       TEXT,
            due_at       REAL,
            start_at     REAL,
            state        TEXT NOT NULL,
            priority     INTEGER NOT NULL DEFAULT 2,
            created_at   REAL NOT NULL,
            loaded_at    REAL,
            touched_at   REAL NOT NULL,
            completed_at REAL,
            pinned       INTEGER NOT NULL DEFAULT 0,
            updated_at   REAL,
            deleted      INTEGER NOT NULL DEFAULT 0,
            dirty        INTEGER NOT NULL DEFAULT 0
        );
        """)
        // Additive migration for databases created before notes existed.
        if !columnExists("kind", in: "items") {
            db.exec("ALTER TABLE items ADD COLUMN kind TEXT NOT NULL DEFAULT 'task';")
        }
        // Additive migration for the optional start date.
        if !columnExists("start_at", in: "items") {
            db.exec("ALTER TABLE items ADD COLUMN start_at REAL;")
        }
        // Sync metadata. Existing rows are queued for the first push.
        if !columnExists("updated_at", in: "items") {
            db.exec("ALTER TABLE items ADD COLUMN updated_at REAL;")
            db.exec("UPDATE items SET updated_at = touched_at WHERE updated_at IS NULL;")
        }
        if !columnExists("deleted", in: "items") {
            db.exec("ALTER TABLE items ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;")
        }
        if !columnExists("dirty", in: "items") {
            db.exec("ALTER TABLE items ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0;")
            db.exec("UPDATE items SET dirty = 1;")
        }
        // Notes have no priority; clear any legacy values so old rows stop
        // carrying one.
        db.exec("""
        UPDATE items
        SET priority = 0, dirty = 1, updated_at = CAST(strftime('%s','now') AS REAL)
        WHERE kind = 'note' AND priority <> 0;
        """)
        db.exec("CREATE INDEX IF NOT EXISTS idx_items_state ON items(state);")
        db.exec("CREATE INDEX IF NOT EXISTS idx_items_completed ON items(completed_at);")
        db.exec("CREATE INDEX IF NOT EXISTS idx_items_kind ON items(kind);")
        db.exec("CREATE INDEX IF NOT EXISTS idx_items_dirty ON items(dirty);")
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        var found = false
        db.query("PRAGMA table_info(\(table));") { row in
            if row.string(1) == column { found = true }
        }
        return found
    }

    // MARK: - Loading

    public func reload() {
        var loaded: [Item] = []
        db.query("""
        SELECT id, kind, text, detail, due_at, state, priority, created_at, loaded_at,
               touched_at, completed_at, pinned, start_at, updated_at, deleted, dirty
        FROM items
        """) { row in
            guard
                let idStr = row.string(0), let id = UUID(uuidString: idStr),
                let text = row.string(2),
                let stateStr = row.string(5), let state = ItemState(rawValue: stateStr)
            else { return }
            let kind = ItemKind(rawValue: row.string(1) ?? "task") ?? .task
            loaded.append(Item(
                id: id,
                kind: kind,
                text: text,
                detail: row.string(3),
                dueAt: row.date(4),
                startAt: row.date(12),
                state: state,
                priority: row.int(6),
                createdAt: row.date(7) ?? Date(),
                loadedAt: row.date(8),
                touchedAt: row.date(9) ?? Date(),
                completedAt: row.date(10),
                pinned: row.bool(11),
                updatedAt: row.date(13) ?? row.date(9) ?? Date(),
                deleted: row.bool(14),
                dirty: row.bool(15)
            ))
        }
        items = loaded
    }

    // MARK: - Sync helpers

    /// Rows with local changes waiting to be pushed (includes tombstones).
    public var dirtyItems: [Item] {
        items.filter { $0.dirty }
    }

    /// Clears the dirty flag after a successful push, without changing `updatedAt`.
    public func markSynced(ids: [UUID]) {
        let set = Set(ids)
        for idx in items.indices where set.contains(items[idx].id) {
            items[idx].dirty = false
            write(items[idx])
        }
    }

    /// Removes tombstones from memory and disk. Sync-only maintenance; tests use it
    /// to isolate runs. Never call while a push is pending.
    func purgeDeleted() {
        let ids = items.filter { $0.deleted }.map(\.id)
        guard !ids.isEmpty else { return }
        items.removeAll { $0.deleted }
        for id in ids {
            db.run("DELETE FROM items WHERE id = ?", [id.uuidString])
        }
    }

    // MARK: - Task queries

    public var loaded: [Item] {
        items.filter { !$0.deleted && $0.kind == .task && $0.state == .loaded }
            .sorted(by: Self.ramOrder)
    }

    public var backlog: [Item] {
        items.filter { !$0.deleted && $0.kind == .task && $0.state == .backlog }
            .sorted(by: Self.ramOrder)
    }

    public var dueNow: [Item] {
        items.filter { !$0.deleted && $0.kind == .task && $0.state == .loaded && $0.isDue }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    public var completed: [Item] {
        items.filter { !$0.deleted && $0.kind == .task && $0.state == .done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    public var badgeCount: Int {
        let due = items.filter { !$0.deleted && $0.kind == .task && $0.state == .loaded && $0.isDue }.count
        return due > 0 ? due : items.filter { !$0.deleted && $0.kind == .task && $0.state == .loaded }.count
    }

    /// Priority desc, then due date, then oldest first. Pinned float to the top.
    public static func ramOrder(_ a: Item, _ b: Item) -> Bool {
        if a.pinned != b.pinned { return a.pinned }
        if a.priority != b.priority { return a.priority > b.priority }
        switch (a.dueAt, b.dueAt) {
        case let (l?, r?) where l != r: return l < r
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        return a.createdAt < b.createdAt
    }

    public func item(id: UUID) -> Item? {
        items.first { $0.id == id && !$0.deleted }
    }

    // MARK: - Note queries

    /// Notes waiting in the inbox, oldest first (review order).
    public var notesInbox: [Item] {
        items.filter { !$0.deleted && $0.kind == .note && $0.state == .inbox }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Journaled notes, newest first.
    public var journaledNotes: [Item] {
        items.filter { !$0.deleted && $0.kind == .note && $0.state == .journaled }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    public var inboxCount: Int { notesInbox.count }

    public var isInboxFull: Bool { notesInbox.count >= max(1, AppSettings.shared.noteCapacity) }

    // MARK: - Task mutations

    @discardableResult
    public func add(text: String, detail: String? = nil, startAt: Date? = nil, dueAt: Date? = nil, priority: Int = 2) -> Item {
        var item = Item(kind: .task,
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        detail: detail,
                        dueAt: dueAt,
                        startAt: startAt,
                        state: .loaded,
                        priority: priority,
                        loadedAt: Date(),
                        touchedAt: Date())
        if item.text.isEmpty { item.text = "(untitled)" }
        insert(item)
        items.append(item)
        enforceCapacity()
        applyTimeWindow()
        return item
    }

    @discardableResult
    public func addNote(text: String, detail: String? = nil) -> Item {
        var item = Item(kind: .note,
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        detail: detail,
                        dueAt: nil,
                        startAt: nil,
                        state: .inbox,
                        priority: 0,
                        loadedAt: nil,
                        touchedAt: Date())
        if item.text.isEmpty { item.text = "(empty note)" }
        insert(item)
        items.append(item)
        return item
    }

    public func update(_ item: Item) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.touchedAt = Date()
        updated.updatedAt = Date()
        updated.dirty = true
        items[idx] = updated
        write(updated)
    }

    public func touch(id: UUID) {
        mutate(id: id) { $0.touchedAt = Date() }
    }

    /// Soft delete: keep the row as a tombstone so the removal can sync.
    public func delete(id: UUID) {
        mutate(id: id) { $0.deleted = true }
    }

    public func complete(id: UUID) {
        mutate(id: id) {
            $0.state = .done
            $0.completedAt = Date()
            $0.touchedAt = Date()
        }
        // Make room in RAM by promoting from the backlog.
        fillWorkingSet()
    }

    public func uncomplete(id: UUID) {
        mutate(id: id) {
            $0.completedAt = nil
            $0.state = .backlog
        }
    }

    /// Bring an item into the working set (respecting capacity).
    public func loadToRAM(id: UUID) {
        mutate(id: id) {
            $0.state = .loaded
            $0.loadedAt = Date()
            $0.touchedAt = Date()
        }
        enforceCapacity()
    }

    /// Spill an item to the "hard drive".
    public func spillToDisk(id: UUID) {
        mutate(id: id) {
            $0.state = .backlog
            $0.loadedAt = nil
        }
    }

    public func togglePin(id: UUID) {
        mutate(id: id) { $0.pinned.toggle() }
    }

    /// Priority is a task-only concept; notes ignore it.
    public func setPriority(id: UUID, _ p: Int) {
        guard item(id: id)?.kind == .task else { return }
        mutate(id: id) { $0.priority = p }
    }

    // MARK: - Note mutations

    /// File a note into the journal, stamping the moment it was reviewed.
    public func journalNote(id: UUID) {
        mutate(id: id) {
            $0.state = .journaled
            $0.completedAt = Date()
            $0.touchedAt = Date()
        }
    }

    /// Put a journaled note back into the inbox.
    public func unjournalNote(id: UUID) {
        mutate(id: id) {
            $0.state = .inbox
            $0.completedAt = nil
        }
    }

    /// Turn a captured thought into an actionable task.
    public func noteToTask(id: UUID) {
        mutate(id: id) {
            $0.kind = .task
            $0.state = .loaded
            $0.priority = 2
            $0.loadedAt = Date()
            $0.touchedAt = Date()
        }
        enforceCapacity()
    }

    // MARK: - RAM rules

    /// If the working set exceeds capacity, spill the weakest item(s) to disk.
    public func enforceCapacity() {
        let limit = max(1, AppSettings.shared.workingSetLimit)
        while loaded.count > limit {
            let spillable = loaded.filter { !$0.pinned }
            guard let victim = spillable.last ?? loaded.last else { break }
            spillToDisk(id: victim.id)
        }
    }

    /// Promote backlog items into RAM until the limit is reached. Items whose
    /// activation is beyond the auto-arrange window are skipped, so RAM holds
    /// what's relevant now; undated items remain eligible.
    public func fillWorkingSet(now: Date = Date()) {
        let limit = max(1, AppSettings.shared.workingSetLimit)
        guard loaded.count < limit else { enforceCapacity(); return }
        let cutoff = Self.windowCutoff(now: now)
        let candidates = backlog.filter { item in
            guard let activation = item.activationAt else { return true }
            return activation <= cutoff
        }.prefix(limit - loaded.count)
        for c in candidates { loadToRAM(id: c.id) }
    }

    /// Auto-arrange the working set around the configured time window:
    /// spill loaded tasks that start too far out, then load backlog tasks
    /// that are now within the window.
    public func applyTimeWindow(now: Date = Date()) {
        guard AppSettings.shared.autoArrangeEnabled else { return }
        let cutoff = Self.windowCutoff(now: now)
        for item in loaded where !item.pinned {
            guard let activation = item.activationAt else { continue }
            if activation > cutoff { spillToDisk(id: item.id) }
        }
        fillWorkingSet(now: now)
    }

    private static func windowCutoff(now: Date = Date()) -> Date {
        let hours = Double(max(0, AppSettings.shared.ramWindowHours))
        return now.addingTimeInterval(hours * 3600)
    }

    /// Spill items that have decayed past the spill threshold. Pinned items are safe.
    public func applyDecay(now: Date = Date()) {
        let spillDays = Double(max(1, AppSettings.shared.decaySpillDays))
        let cutoff = now.addingTimeInterval(-spillDays * 86_400)
        for item in loaded where !item.pinned && item.touchedAt < cutoff {
            spillToDisk(id: item.id)
        }
    }

    // MARK: - Persistence

    /// Applies an in-place mutation, stamps sync metadata, and persists.
    private func mutate(id: UUID, _ body: (inout Item) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[idx])
        items[idx].updatedAt = Date()
        items[idx].dirty = true
        write(items[idx])
    }

    private func insert(_ item: Item) {
        db.run("""
        INSERT INTO items (id, kind, text, detail, due_at, state, priority, created_at,
                           loaded_at, touched_at, completed_at, pinned, start_at,
                           updated_at, deleted, dirty)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            item.id.uuidString, item.kind.rawValue, item.text, item.detail, item.dueAt, item.state.rawValue,
            item.priority, item.createdAt, item.loadedAt, item.touchedAt, item.completedAt, item.pinned,
            item.startAt, item.updatedAt, item.deleted, item.dirty,
        ])
    }

    private func write(_ item: Item) {
        db.run("""
        UPDATE items SET kind = ?, text = ?, detail = ?, due_at = ?, state = ?, priority = ?,
                         created_at = ?, loaded_at = ?, touched_at = ?, completed_at = ?, pinned = ?,
                         start_at = ?, updated_at = ?, deleted = ?, dirty = ?
        WHERE id = ?
        """, [
            item.kind.rawValue, item.text, item.detail, item.dueAt, item.state.rawValue, item.priority,
            item.createdAt, item.loadedAt, item.touchedAt, item.completedAt, item.pinned,
            item.startAt, item.updatedAt, item.deleted, item.dirty, item.id.uuidString,
        ])
    }
}
