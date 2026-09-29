import Foundation
import Combine
import WidgetKit
import HumanRAMShared

/// Versioned, portable snapshot of the whole store, used for export/import
/// (manual backups and device migration).
public struct ItemArchive: Codable {
    public var version: Int
    public var exportedAt: Date
    public var items: [Item]

    public init(version: Int = 1, exportedAt: Date = Date(), items: [Item]) {
        self.version = version
        self.exportedAt = exportedAt
        self.items = items
    }
}

/// In-memory working copy of all items, write-through to SQLite.
public final class ItemStore: ObservableObject {
    public static let shared = ItemStore()

    /// Bumped whenever the schema changes so an upgrade can snapshot the old
    /// database before migrating it.
    public static let schemaVersion = 4

    /// Every row, including tombstones (`deleted == true`). UI queries filter deleted rows;
    /// tombstones are kept so removals can propagate during sync.
    @Published public private(set) var items: [Item] = []
    private var db: Database
    private let sharesWithWidget: Bool
    public let databaseURL: URL
    /// Set when an unreadable database was moved aside on launch so the UI can say so.
    public private(set) var quarantinedDatabaseURL: URL?
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
        databaseURL = URL(fileURLWithPath: path)
        let existed = FileManager.default.fileExists(atPath: path)
        db = Database(path: path)
        // Never crash on a damaged file: move it aside and start clean.
        var migratedFromExistingFile = existed
        if existed && (!db.isOpen || !db.quickCheck()) {
            quarantineCorruptDatabase()
            db = Database(path: path)
            migratedFromExistingFile = false
        }
        migrate(wasExistingDatabase: migratedFromExistingFile)
        reload()
        $items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.publishWidgetSnapshot() }
            .store(in: &cancellables)
    }

    private func quarantineCorruptDatabase() {
        db.close()
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let moved = databaseURL.path + ".corrupt-\(stamp)"
        // Fold the WAL into the main file first so the quarantined copy is complete.
        try? fm.moveItem(atPath: databaseURL.path, toPath: moved)
        for suffix in ["-wal", "-shm"] {
            try? fm.removeItem(atPath: databaseURL.path + suffix)
        }
        quarantinedDatabaseURL = URL(fileURLWithPath: moved)
        NSLog("HumanRAM: database failed its integrity check; moved to \(moved) and started fresh.")
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

    private func migrate(wasExistingDatabase: Bool) {
        guard db.isOpen else { return }
        let existingVersion = schemaVersionOnDisk()
        // Snapshot the old file before applying an additive migration so an
        // upgrade can always be rolled back by hand.
        if wasExistingDatabase && existingVersion < Self.schemaVersion {
            backupDatabase(label: "pre-\(existingVersion)")
        }
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
        db.exec("PRAGMA user_version = \(Self.schemaVersion);")
    }

    private func schemaVersionOnDisk() -> Int {
        var version = 0
        db.query("PRAGMA user_version;") { row in version = row.int(0) }
        return version
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        var found = false
        db.query("PRAGMA table_info(\(table));") { row in
            if row.string(1) == column { found = true }
        }
        return found
    }

    // MARK: - Backup / export

    /// A point-in-time copy of the database, in a `Backups` folder beside it.
    @discardableResult
    public func backupDatabase(label: String = "manual") -> URL? {
        guard db.isOpen else { return nil }
        db.checkpoint()
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let dir = databaseURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("humanram-\(label)-\(stamp).sqlite3")
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: databaseURL, to: dest)
            return dest
        } catch {
            NSLog("HumanRAM backup failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// All items (including tombstones) as a portable JSON archive.
    public func exportArchiveData(pretty: Bool = true) throws -> Data {
        let archive = ItemArchive(exportedAt: Date(), items: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(archive)
    }

    /// Merges a JSON archive by UUID, keeping the newer mutation for each item.
    /// Returns the number of items added or updated. Any archive shape is
    /// tolerated; malformed input throws instead of mutating the store.
    @discardableResult
    public func importArchive(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ItemArchive.self, from: data)
        var imported = 0
        db.transaction {
            for incoming in archive.items {
                if let idx = items.firstIndex(where: { $0.id == incoming.id }) {
                    guard incoming.updatedAt > items[idx].updatedAt else { continue }
                    var merged = incoming
                    merged.dirty = true
                    items[idx] = merged
                    write(merged)
                    imported += 1
                } else {
                    var fresh = incoming
                    fresh.dirty = true
                    items.append(fresh)
                    insert(fresh)
                    imported += 1
                }
            }
        }
        if imported > 0 {
            enforceCapacity()
            applyTimeWindow()
            fillWorkingSet()
        }
        return imported
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
        enforceCapacity(protecting: item.id)
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
        // An edit can move a task in or out of the window (or push RAM over
        // capacity), so re-apply the same rules as add/load.
        enforceCapacity(protecting: updated.id)
        applyTimeWindow()
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
            $0.loadedAt = nil
        }
    }

    /// Bring an item into the working set (respecting capacity).
    public func loadToRAM(id: UUID) {
        mutate(id: id) {
            $0.state = .loaded
            $0.loadedAt = Date()
            $0.touchedAt = Date()
        }
        enforceCapacity(protecting: id)
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
        enforceCapacity(protecting: id)
    }

    // MARK: - RAM rules

    /// If the working set exceeds capacity, spill the weakest item(s) to disk.
    /// Pinned items are never auto-spilled. `protecting` keeps the item that
    /// just arrived (captured or loaded) so the action isn't immediately undone.
    public func enforceCapacity(protecting protectedID: UUID? = nil) {
        let limit = max(1, AppSettings.shared.workingSetLimit)
        while loaded.count > limit {
            let spillable = loaded.filter { !$0.pinned && $0.id != protectedID }
            guard let victim = spillable.last else { break }
            spillToDisk(id: victim.id)
        }
    }

    /// Promote backlog items into RAM until the limit is reached. Dated items
    /// must be inside the auto-arrange window. Undated items are eligible only
    /// when `includeUndated`: the continuous auto-arrange passes `false` so it
    /// doesn't resurrect something the user just spilled, while completing a
    /// task uses the default to keep RAM full. Stale items stay on the disk.
    public func fillWorkingSet(now: Date = Date(), includeUndated: Bool = true) {
        let limit = max(1, AppSettings.shared.workingSetLimit)
        guard loaded.count < limit else { enforceCapacity(); return }
        let cutoff = Self.windowCutoff(now: now)
        let staleBefore = now.addingTimeInterval(-Double(max(1, AppSettings.shared.decaySpillDays)) * 86_400)
        let candidates = backlog.filter { item in
            guard let activation = item.activationAt else {
                return includeUndated && item.touchedAt >= staleBefore
            }
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
        fillWorkingSet(now: now, includeUndated: false)
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
