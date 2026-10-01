import XCTest
import AppKit
@testable import HumanRAMCore

final class HumanRAMTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        // Isolate every test run from the real database.
        let path = NSTemporaryDirectory() + "hram-test-\(UUID().uuidString).sqlite3"
        setenv("HRAM_DB_PATH", path, 1)
    }

    private var store: ItemStore { ItemStore.shared }

    private func clearAll() {
        for item in store.items { store.delete(id: item.id) }
        store.purgeDeleted()
    }

    // MARK: - Tasks

    func testCapacitySpillsToBacklog() {
        clearAll()
        let original = AppSettings.shared.workingSetLimit
        AppSettings.shared.workingSetLimit = 2
        defer { AppSettings.shared.workingSetLimit = original }

        for i in 0..<5 { store.add(text: "task \(i)") }
        XCTAssertEqual(store.loaded.count, 2, "working set respects capacity")
        XCTAssertEqual(store.backlog.count, 3, "overflow spills to the hard drive")
        XCTAssertEqual(store.items.count, 5, "nothing is lost")
    }

    func testNewTaskStaysInRAMWhenAtCapacity() {
        clearAll()
        let original = AppSettings.shared.workingSetLimit
        AppSettings.shared.workingSetLimit = 2
        defer { AppSettings.shared.workingSetLimit = original }

        let first = store.add(text: "first")
        let second = store.add(text: "second")
        let newest = store.add(text: "newest")

        XCTAssertEqual(store.loaded.count, 2, "capacity still holds")
        XCTAssertTrue(store.loaded.contains { $0.id == newest.id }, "a fresh capture stays in RAM")
        XCTAssertTrue(store.loaded.contains { $0.id == first.id })
        XCTAssertFalse(store.loaded.contains { $0.id == second.id }, "an older task makes room instead")
    }

    func testCapacityNeverSpillsPinnedItems() {
        clearAll()
        let original = AppSettings.shared.workingSetLimit
        AppSettings.shared.workingSetLimit = 3
        defer { AppSettings.shared.workingSetLimit = original }

        let a = store.add(text: "a")
        let b = store.add(text: "b")
        let c = store.add(text: "c")
        for id in [a.id, b.id, c.id] { store.togglePin(id: id) }

        AppSettings.shared.workingSetLimit = 1
        store.enforceCapacity()

        XCTAssertEqual(store.loaded.count, 3, "pinned items are never auto-spilled, even over capacity")
        for id in [a.id, b.id, c.id] {
            XCTAssertEqual(store.item(id: id)?.state, .loaded)
        }
    }

    func testManualLoadStaysInRAMWhenAtCapacity() {
        clearAll()
        let original = AppSettings.shared.workingSetLimit
        AppSettings.shared.workingSetLimit = 2
        defer { AppSettings.shared.workingSetLimit = original }

        store.add(text: "a")
        store.add(text: "b")
        let far = store.add(text: "far", startAt: Date().addingTimeInterval(1000 * 3600))
        XCTAssertEqual(store.item(id: far.id)?.state, .backlog, "beyond the window it spills")

        store.loadToRAM(id: far.id)
        XCTAssertEqual(store.item(id: far.id)?.state, .loaded, "a manually loaded task makes room for itself")
        XCTAssertEqual(store.loaded.count, 2)
    }

    func testCompleteFilesToDiaryAndRefills() {
        clearAll()
        let original = AppSettings.shared.workingSetLimit
        AppSettings.shared.workingSetLimit = 1
        defer { AppSettings.shared.workingSetLimit = original }

        let a = store.add(text: "first")
        store.add(text: "second")
        XCTAssertEqual(store.loaded.count, 1)

        store.complete(id: a.id)
        XCTAssertEqual(store.completed.count, 1)
        XCTAssertNotNil(store.completed.first?.completedAt)
        XCTAssertEqual(store.loaded.count, 1, "a backlog item is promoted to fill RAM")
    }

    func testRamOrderPrefersPinnedThenPriority() {
        clearAll()
        let low = store.add(text: "low", priority: 1)
        let high = store.add(text: "high", priority: 3)
        store.togglePin(id: low.id)
        let ordered = store.loaded
        XCTAssertEqual(ordered.first?.id, low.id, "pinned floats to the top")
        XCTAssertEqual(ordered.last?.id, high.id)
    }

    // MARK: - Time window

    func testTimeWindowSpillsFarAndLoadsNear() {
        clearAll()
        let originalEnabled = AppSettings.shared.autoArrangeEnabled
        let originalWindow = AppSettings.shared.ramWindowHours
        AppSettings.shared.autoArrangeEnabled = true
        AppSettings.shared.ramWindowHours = 48
        defer {
            AppSettings.shared.autoArrangeEnabled = originalEnabled
            AppSettings.shared.ramWindowHours = originalWindow
        }

        let far = store.add(text: "far future", startAt: Date().addingTimeInterval(72 * 3600))
        XCTAssertEqual(store.item(id: far.id)?.state, .backlog, "a task starting beyond the window spills")

        let near = store.add(text: "starting soon", startAt: Date().addingTimeInterval(2 * 3600))
        store.spillToDisk(id: near.id)
        store.applyTimeWindow()
        XCTAssertEqual(store.item(id: near.id)?.state, .loaded, "a task entering the window loads")
        XCTAssertFalse(store.loaded.contains { $0.id == far.id }, "the far task stays on the hard drive")
    }

    func testTimeWindowLeavesUndatedTasksAlone() {
        clearAll()
        let task = store.add(text: "no schedule")
        store.applyTimeWindow()
        XCTAssertEqual(store.item(id: task.id)?.state, .loaded, "undated tasks remain in RAM")
    }

    func testPinnedFarTaskIsNotSpilled() {
        clearAll()
        let originalEnabled = AppSettings.shared.autoArrangeEnabled
        let originalWindow = AppSettings.shared.ramWindowHours
        AppSettings.shared.autoArrangeEnabled = false
        AppSettings.shared.ramWindowHours = 48
        defer {
            AppSettings.shared.autoArrangeEnabled = originalEnabled
            AppSettings.shared.ramWindowHours = originalWindow
        }

        let pinned = store.add(text: "pinned far", startAt: Date().addingTimeInterval(96 * 3600))
        store.togglePin(id: pinned.id)
        AppSettings.shared.autoArrangeEnabled = true
        store.applyTimeWindow()
        XCTAssertEqual(store.item(id: pinned.id)?.state, .loaded, "pinned tasks survive the window")
    }

    func testDecaySpillIsNotUndoneByAutoArrange() {
        clearAll()
        let originalEnabled = AppSettings.shared.autoArrangeEnabled
        let originalWindow = AppSettings.shared.ramWindowHours
        let originalSpill = AppSettings.shared.decaySpillDays
        AppSettings.shared.autoArrangeEnabled = true
        AppSettings.shared.ramWindowHours = 48
        AppSettings.shared.decaySpillDays = 10
        defer {
            AppSettings.shared.autoArrangeEnabled = originalEnabled
            AppSettings.shared.ramWindowHours = originalWindow
            AppSettings.shared.decaySpillDays = originalSpill
        }

        let stale = store.add(text: "stale")
        let later = Date().addingTimeInterval(11 * 86_400)
        store.applyDecay(now: later)
        store.applyTimeWindow(now: later)

        XCTAssertEqual(store.item(id: stale.id)?.state, .backlog, "a decayed task stays on the hard drive")
    }

    func testManualSpillIsNotUndoneByAutoArrange() {
        clearAll()
        let originalEnabled = AppSettings.shared.autoArrangeEnabled
        let originalWindow = AppSettings.shared.ramWindowHours
        AppSettings.shared.autoArrangeEnabled = true
        AppSettings.shared.ramWindowHours = 48
        defer {
            AppSettings.shared.autoArrangeEnabled = originalEnabled
            AppSettings.shared.ramWindowHours = originalWindow
        }

        let task = store.add(text: "spill me")
        store.spillToDisk(id: task.id)
        store.applyTimeWindow()

        XCTAssertEqual(store.item(id: task.id)?.state, .backlog, "an undated spill stays on the hard drive")
    }

    func testEditingTaskBeyondWindowSpillsIt() {
        clearAll()
        let originalEnabled = AppSettings.shared.autoArrangeEnabled
        let originalWindow = AppSettings.shared.ramWindowHours
        AppSettings.shared.autoArrangeEnabled = true
        AppSettings.shared.ramWindowHours = 48
        defer {
            AppSettings.shared.autoArrangeEnabled = originalEnabled
            AppSettings.shared.ramWindowHours = originalWindow
        }

        var task = store.add(text: "soon", startAt: Date().addingTimeInterval(2 * 3600))
        XCTAssertEqual(store.item(id: task.id)?.state, .loaded)

        task.startAt = Date().addingTimeInterval(72 * 3600)
        store.update(task)

        XCTAssertEqual(store.item(id: task.id)?.state, .backlog, "editing beyond the window spills the task")
    }

    // MARK: - Notes

    func testNoteCaptureAndJournal() {
        clearAll()
        let note = store.addNote(text: "shower thought")
        XCTAssertTrue(note.isNote)
        XCTAssertEqual(store.inboxCount, 1)
        XCTAssertFalse(store.notesInbox.isEmpty)

        store.journalNote(id: note.id)
        XCTAssertEqual(store.inboxCount, 0)
        XCTAssertEqual(store.journaledNotes.count, 1)
        XCTAssertNotNil(store.journaledNotes.first?.completedAt, "journaling stamps a time")
        XCTAssertEqual(store.journaledNotes.first?.createdAt, note.createdAt, "capture time preserved")
    }

    func testNoteToTaskEntersRAM() {
        clearAll()
        let note = store.addNote(text: "idea that is really a todo")
        store.noteToTask(id: note.id)

        XCTAssertEqual(store.inboxCount, 0)
        XCTAssertTrue(store.loaded.contains { $0.id == note.id }, "converted note is now a loaded task")
        XCTAssertFalse(store.item(id: note.id)?.isNote ?? true)
        XCTAssertEqual(store.item(id: note.id)?.priority, 2, "a converted note starts at normal priority")
    }

    func testNotesHaveNoPriority() {
        clearAll()
        let note = store.addNote(text: "no priority please")
        XCTAssertEqual(store.item(id: note.id)?.priority, 0, "notes are created without priority")

        store.setPriority(id: note.id, 3)
        XCTAssertEqual(store.item(id: note.id)?.priority, 0, "priority cannot be set on a note")
    }

    func testInboxFullFlag() {
        clearAll()
        let original = AppSettings.shared.noteCapacity
        AppSettings.shared.noteCapacity = 3
        defer { AppSettings.shared.noteCapacity = original }

        for i in 0..<3 { store.addNote(text: "note \(i)") }
        XCTAssertTrue(store.isInboxFull)

        // Overflow is allowed, per design — nothing auto-files.
        store.addNote(text: "note beyond capacity")
        XCTAssertEqual(store.inboxCount, 4)
        XCTAssertEqual(store.journaledNotes.count, 0, "no auto-journaling")
    }

    func testNotesDoNotAppearInTaskViews() {
        clearAll()
        store.addNote(text: "a thought")
        XCTAssertTrue(store.loaded.isEmpty, "notes never enter the task working set")
        XCTAssertTrue(store.backlog.isEmpty)
        XCTAssertTrue(store.completed.isEmpty)
        XCTAssertEqual(store.badgeCount, 0, "notes don't affect the task badge")
    }

    // MARK: - Sync metadata

    func testNewItemsAreDirty() {
        clearAll()
        let task = store.add(text: "fresh task")
        let note = store.addNote(text: "fresh note")
        XCTAssertTrue(store.item(id: task.id)?.dirty ?? false)
        XCTAssertTrue(store.item(id: note.id)?.dirty ?? false)
        XCTAssertEqual(store.dirtyItems.count, 2)
    }

    func testSoftDeleteKeepsTombstone() {
        clearAll()
        let item = store.add(text: "delete me")
        store.delete(id: item.id)

        XCTAssertTrue(store.loaded.isEmpty, "deleted rows vanish from queries")
        XCTAssertNil(store.item(id: item.id), "deleted rows are not addressable")
        XCTAssertEqual(store.badgeCount, 0)
        XCTAssertTrue(store.items.contains { $0.id == item.id && $0.deleted }, "tombstone retained")
        XCTAssertTrue(store.dirtyItems.contains { $0.id == item.id }, "tombstone needs pushing")

        store.reload()
        XCTAssertTrue(store.items.contains { $0.id == item.id && $0.deleted }, "tombstone persists to disk")
    }

    func testMutationStampsUpdatedAtAndDirty() {
        clearAll()
        let item = store.add(text: "stamp me")
        store.markSynced(ids: [item.id])
        let before = try! XCTUnwrap(store.item(id: item.id))
        XCTAssertFalse(before.dirty)
        XCTAssertTrue(store.dirtyItems.isEmpty)

        store.setPriority(id: item.id, 3)
        let after = try! XCTUnwrap(store.item(id: item.id))
        XCTAssertTrue(after.dirty, "mutations dirty the row")
        XCTAssertGreaterThanOrEqual(after.updatedAt, before.updatedAt, "mutations bump updatedAt")
        XCTAssertEqual(store.dirtyItems.count, 1)
    }

    func testSoftDeletedNotesLeaveInbox() {
        clearAll()
        let note = store.addNote(text: "fleeting")
        XCTAssertEqual(store.inboxCount, 1)
        store.delete(id: note.id)
        XCTAssertEqual(store.inboxCount, 0)
        XCTAssertTrue(store.notesInbox.isEmpty)
    }

    func testUncompleteReturnsToBacklog() {
        clearAll()
        let item = store.add(text: "done then not")
        store.complete(id: item.id)
        XCTAssertEqual(store.item(id: item.id)?.state, .done)

        store.uncomplete(id: item.id)
        XCTAssertEqual(store.item(id: item.id)?.state, .backlog)
        XCTAssertNil(store.item(id: item.id)?.completedAt)
    }

    func testDecaySpillsStaleButKeepsPinned() {
        clearAll()
        let original = AppSettings.shared.decaySpillDays
        AppSettings.shared.decaySpillDays = 10
        defer { AppSettings.shared.decaySpillDays = original }

        let stale = store.add(text: "stale")
        let pinned = store.add(text: "pinned")
        store.togglePin(id: pinned.id)

        store.applyDecay(now: Date().addingTimeInterval(11 * 86_400))

        XCTAssertEqual(store.item(id: stale.id)?.state, .backlog, "an untouched task spills after the decay window")
        XCTAssertEqual(store.item(id: pinned.id)?.state, .loaded, "pinned tasks survive decay")
    }

    func testTimeWindowHonoursInjectedClock() {
        clearAll()
        let originalEnabled = AppSettings.shared.autoArrangeEnabled
        let originalWindow = AppSettings.shared.ramWindowHours
        AppSettings.shared.autoArrangeEnabled = true
        AppSettings.shared.ramWindowHours = 48
        defer {
            AppSettings.shared.autoArrangeEnabled = originalEnabled
            AppSettings.shared.ramWindowHours = originalWindow
        }

        let base = Date()
        let task = store.add(text: "later", startAt: base.addingTimeInterval(72 * 3600))
        XCTAssertEqual(store.item(id: task.id)?.state, .backlog, "a task beyond the window spills")

        store.applyTimeWindow(now: base.addingTimeInterval(80 * 3600))
        XCTAssertEqual(store.item(id: task.id)?.state, .loaded, "the clock catching up loads it back")
    }

    // MARK: - Numeric date parsing

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testNumericDateParserReadsComponents() {
        let stamp = NumericDateParser.parse("09231920")
        XCTAssertEqual(stamp.month, 9)
        XCTAssertEqual(stamp.day, 23)
        XCTAssertEqual(stamp.hour, 19)
        XCTAssertEqual(stamp.minute, 20)
        XCTAssertTrue(stamp.hasDate)
        XCTAssertTrue(stamp.hasTime)
        XCTAssertTrue(stamp.isComplete)
        XCTAssertTrue(stamp.isValid)
    }

    func testNumericDateParserSanitizesInput() {
        XCTAssertEqual(NumericDateParser.sanitize("09/23 19:20"), "09231920", "separators are ignored")
        XCTAssertEqual(NumericDateParser.sanitize("abcdef"), "")
        XCTAssertEqual(NumericDateParser.sanitize("1234567890"), "12345678", "capped at eight digits")

        let partial = NumericDateParser.parse("09")
        XCTAssertEqual(partial.month, 9)
        XCTAssertNil(partial.day)
        XCTAssertFalse(partial.hasDate)
    }

    func testNumericDateParserRejectsOutOfRangeComponents() {
        XCTAssertFalse(NumericDateParser.parse("1399").isValid, "month 13 is invalid")
        XCTAssertFalse(NumericDateParser.parse("12325900").isValid, "day 32 / hour 59 are invalid")
        XCTAssertTrue(NumericDateParser.parse("02291500").isValid, "in range, even if not a real date")
    }

    func testNumericDateParserRollsPastDatesForward() {
        let cal = utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!

        let past = NumericDateParser.parse("01011500")
        let rolled = NumericDateParser.date(from: past, year: 2026, now: now, calendar: cal)
        XCTAssertEqual(rolled?.year, 2027, "a past date means next year")
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: rolled!.date)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, 15)

        let future = NumericDateParser.parse("12311500")
        let kept = NumericDateParser.date(from: future, year: 2026, now: now, calendar: cal)
        XCTAssertEqual(kept?.year, 2026, "a future date stays put")
    }

    func testNumericDateParserResolvesDateWithoutMinutes() {
        let cal = utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!

        // A day-only stamp is not "complete", but it still resolves — this is
        // what lets the date field commit a typed date before minutes are added.
        let dayOnly = NumericDateParser.parse("0923")
        XCTAssertTrue(dayOnly.hasDate)
        XCTAssertFalse(dayOnly.isComplete)
        let resolved = NumericDateParser.date(from: dayOnly, year: 2026, now: now, calendar: cal)
        XCTAssertNotNil(resolved)

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: resolved!.date)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.day, 23)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func testNumericDateParserKeepsSameDayTypedDates() {
        let cal = utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 0, minute: 30))!

        // Midnight today is technically in the past, but a same-day date must
        // stay put instead of rolling a full year.
        let today = NumericDateParser.parse("0928")
        let resolved = NumericDateParser.date(from: today, year: 2026, now: now, calendar: cal)
        XCTAssertEqual(resolved?.year, 2026, "today's date is not next year")
        let comps = cal.dateComponents([.year, .month, .day], from: resolved!.date)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.day, 28)

        // An earlier time today is kept too, not rolled a year.
        let earlier = NumericDateParser.parse("09280800")
        let kept = NumericDateParser.date(from: earlier, year: 2026, now: now, calendar: cal)
        XCTAssertEqual(kept?.year, 2026)
    }

    func testNumericDateParserKeepsDatesWithinGraceWindow() {
        let cal = utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!

        // A near-past date still belongs to this year.
        let twoDaysAgo = NumericDateParser.parse("0924")
        XCTAssertEqual(
            NumericDateParser.date(from: twoDaysAgo, year: 2026, now: now, calendar: cal)?.year,
            2026, "a date two days back is this year"
        )

        // Exactly three days before today is the boundary and is still kept.
        let threeDaysAgo = NumericDateParser.parse("0923")
        XCTAssertEqual(
            NumericDateParser.date(from: threeDaysAgo, year: 2026, now: now, calendar: cal)?.year,
            2026, "three days back is the edge of the grace window"
        )

        // More than three days before today rolls forward to next year.
        let fourDaysAgo = NumericDateParser.parse("0922")
        XCTAssertEqual(
            NumericDateParser.date(from: fourDaysAgo, year: 2026, now: now, calendar: cal)?.year,
            2027, "more than three days back means next year"
        )
    }

    func testNumericDateParserCanSkipRollForward() {
        let cal = utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!
        let past = NumericDateParser.parse("01011500")
        let kept = NumericDateParser.date(from: past, year: 2026, now: now, rollForward: false, calendar: cal)
        XCTAssertEqual(kept?.year, 2026)
    }

    func testNumericDateParserRejectsImpossibleDate() {
        let cal = utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!
        let feb30 = NumericDateParser.parse("02301500")
        XCTAssertNil(NumericDateParser.date(from: feb30, year: 2023, now: now, calendar: cal), "Feb 30 is not a real day")
    }

    // MARK: - Freshness / formatting

    func testFreshnessTracksLastTouch() {
        let now = Date()
        let fresh = Item(text: "x", state: .loaded, touchedAt: now)
        XCTAssertEqual(fresh.freshness(decayDimDays: 3, now: now), 1, accuracy: 0.001)

        let half = Item(text: "y", state: .loaded, touchedAt: now.addingTimeInterval(-1.5 * 86_400))
        XCTAssertEqual(half.freshness(decayDimDays: 3, now: now), 0.5, accuracy: 0.001)

        let stale = Item(text: "z", state: .loaded, touchedAt: now.addingTimeInterval(-6 * 86_400))
        XCTAssertEqual(stale.freshness(decayDimDays: 3, now: now), 0, accuracy: 0.001)

        let spilled = Item(text: "b", state: .backlog, touchedAt: now.addingTimeInterval(-6 * 86_400))
        XCTAssertEqual(spilled.freshness(decayDimDays: 3, now: now), 1, "backlog items don't dim")
    }

    func testDueFormatShowsTimeOnlyWhenSet() {
        let cal = Calendar.current
        let midnight = cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 0, minute: 0))!
        let afternoon = cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 19, minute: 20))!
        XCTAssertFalse(DueFormat.format(midnight).contains(":"), "midnight has no time suffix")
        XCTAssertTrue(DueFormat.format(afternoon).contains(":"), "a set time is shown")
    }

    // MARK: - Keyboard shortcuts

    private func keyEvent(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, _ characters: String) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    func testPriorityShortcutsMapCommandDigits() {
        XCTAssertEqual(keyEvent(18, [.command], "1").flatMap(Shortcuts.priority(for:)), 0)
        XCTAssertEqual(keyEvent(21, [.command], "4").flatMap(Shortcuts.priority(for:)), 3)
        XCTAssertNil(keyEvent(18, [], "1").flatMap(Shortcuts.priority(for:)), "command is required")
        XCTAssertNil(keyEvent(18, [.command], "5").flatMap(Shortcuts.priority(for:)), "only ⌘1–⌘4")
    }

    func testEditingShortcutsMapKeys() {
        XCTAssertTrue(keyEvent(36, [.command], "\r").map(Shortcuts.isStore) ?? false, "⌘⏎ stores")
        XCTAssertTrue(keyEvent(36, [.option], "\r").map(Shortcuts.isDetail) ?? false, "⌥⏎ opens notes")
        XCTAssertFalse(keyEvent(36, [], "\r").map(Shortcuts.isStore) ?? true, "plain ⏎ is not a store")
        XCTAssertTrue(keyEvent(48, [], "\t").map(Shortcuts.isTab) ?? false)
        XCTAssertTrue(keyEvent(53, [], "\u{1b}").map(Shortcuts.isCancel) ?? false)
    }

    // MARK: - Export / import

    func testArchiveRoundTripRestoresItems() throws {
        clearAll()
        store.add(text: "pay rent", priority: 3)
        store.addNote(text: "essay idea")

        let data = try store.exportArchiveData()
        clearAll()
        XCTAssertTrue(store.items.filter { !$0.deleted }.isEmpty, "store is empty before import")

        let imported = try store.importArchive(data)
        XCTAssertEqual(imported, 2, "both items come back")
        XCTAssertTrue(store.loaded.contains { $0.text == "pay rent" })
        XCTAssertEqual(store.notesInbox.first?.text, "essay idea")
    }

    func testImportKeepsNewestMutation() throws {
        clearAll()
        let item = store.add(text: "old text")
        let archive = try store.exportArchiveData()

        var edited = item
        edited.text = "newer text"
        edited.updatedAt = Date().addingTimeInterval(60)
        store.update(edited)

        let changed = try store.importArchive(archive)
        XCTAssertEqual(changed, 0, "an older archive does not clobber a newer edit")
        XCTAssertEqual(store.item(id: item.id)?.text, "newer text")
    }

    func testImportGarbageThrowsWithoutMutating() {
        clearAll()
        store.add(text: "keep me")
        let before = store.items.count
        XCTAssertThrowsError(try store.importArchive(Data("not json".utf8)))
        XCTAssertEqual(store.items.count, before, "a failed import changes nothing")
    }

    func testBackupWritesACopy() throws {
        clearAll()
        store.add(text: "backup target")
        let url = try XCTUnwrap(store.backupDatabase(label: "test"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.contains("test"))
    }

    // MARK: - Update checker

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer([0, 2, 1], than: [0, 2, 0]))
        XCTAssertFalse(UpdateChecker.isNewer([0, 2, 0], than: [0, 2, 0]))
        XCTAssertTrue(UpdateChecker.isNewer([1, 0, 0], than: [0, 9, 9]))
        XCTAssertTrue(UpdateChecker.isNewer([0, 3], than: [0, 2, 9]))
    }

    func testUpdateEvaluationPicksNewestStable() throws {
        let json = Data("""
        [
          {"tag_name":"v0.3.0","name":"beta","html_url":"https://example.com/b","body":"","draft":false,"prerelease":true},
          {"tag_name":"v0.2.1","name":"patch","html_url":"https://example.com/p","body":"","draft":false,"prerelease":false},
          {"tag_name":"v0.2.0","name":"old","html_url":"https://example.com/o","body":"","draft":false,"prerelease":false}
        ]
        """.utf8)
        let result = UpdateChecker.evaluate(data: json, error: nil, currentVersion: "0.2.0")
        guard case .success(let release) = result else { return XCTFail("expected success") }
        XCTAssertEqual(release?.version, "0.2.1", "prerelease is ignored")
    }

    // MARK: - Appearance

    func testAppAppearanceOptions() {
        XCTAssertEqual(AppAppearance.allCases.count, 3)
        XCTAssertEqual(AppAppearance.system.label, "System")
        XCTAssertEqual(AppAppearance.light.label, "Light")
        XCTAssertEqual(AppAppearance.dark.label, "Dark")
        XCTAssertEqual(AppAppearance(rawValue: "dark"), .dark)
        XCTAssertNil(AppAppearance(rawValue: "neon"))
    }

    func testAppearanceSettingRoundTrips() {
        let original = AppSettings.shared.appearance
        defer { AppSettings.shared.appearance = original }
        AppSettings.shared.appearance = .dark
        XCTAssertEqual(AppSettings.shared.appearance, .dark)
        AppSettings.shared.appearance = .light
        XCTAssertEqual(AppSettings.shared.appearance, .light)
    }

    func testUpdateEvaluationUpToDateReturnsNothing() throws {
        let json = Data("""
        [{"tag_name":"v0.2.0","name":"current","html_url":"https://example.com/c","body":"","draft":false,"prerelease":false}]
        """.utf8)
        let result = UpdateChecker.evaluate(data: json, error: nil, currentVersion: "0.2.0")
        guard case .success(let release) = result else { return XCTFail("expected success") }
        XCTAssertNil(release)
    }
}