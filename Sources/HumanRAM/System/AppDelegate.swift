import AppKit
import HumanRAMCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let taskHotKey = HotKey(id: 1)
    private var priorityMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installRouter()
        registerHotKeys()
        installPriorityMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registerHotKeys),
            name: .humanRAMHotKeyChanged,
            object: nil
        )
        Scheduler.shared.start(store: ItemStore.shared)
        runDebugHooksIfNeeded()
        showGuideIfNeeded()
    }

    private func showGuideIfNeeded() {
        guard AppSettings.shared.showGuideOnLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            WindowManager.shared.showGuide()
        }
    }

    /// One app-level monitor turns `⌘1`–`⌘4` into a window-addressed notification
    /// so priority works in every editing surface without opening the priority
    /// menu, and so the key never falls through to the system (which beeps).
    private func installPriorityMonitor() {
        priorityMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The capture panel handles its own keys (see CapturePanelWindow),
            // including when the app is inactive and local monitors are skipped.
            if event.window is CapturePanelWindow { return event }
            // Tab in the menu-bar window switches between task and note.
            if Shortcuts.isTab(event),
               let menuBar = HumanRAMWindows.menuBar,
               event.window === menuBar {
                NotificationCenter.default.post(name: .humanRAMToggleCaptureMode, object: event.window)
                return nil
            }
            guard let priority = Shortcuts.priority(for: event) else { return event }
            NotificationCenter.default.post(
                name: .humanRAMSetPriority,
                object: event.window,
                userInfo: [HumanRAMNotificationKey.priority: priority]
            )
            return nil
        }
    }

    /// Connects the portable core's navigation seam to macOS windows.
    private func installRouter() {
        let router = AppRouter.shared
        router.presentDailyScan = { WindowManager.shared.showDigest() }
        router.presentNotesReview = { WindowManager.shared.showNotesReview() }
        router.presentEditItem = { WindowManager.shared.showEdit(itemID: $0) }
        router.presentGuide = { WindowManager.shared.showGuide() }
        router.dismissActiveWindow = { NSApp.keyWindow?.close() }
    }

    @objc private func registerHotKeys() {
        let settings = AppSettings.shared
        taskHotKey.register(
            keyCode: UInt32(settings.hotkeyKeyCode),
            modifiers: UInt32(settings.hotkeyModifiers)
        ) {
            CapturePanel.shared.toggle(mode: .task)
        }
    }

    /// Development aid: `HRAM_DEBUG_SEED=1` seeds sample data,
    /// `HRAM_DEBUG_OPEN=1` opens every window so all views render.
    private func runDebugHooksIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        if env["HRAM_DEBUG_SEED"] != nil {
            let store = ItemStore.shared
            if store.items.isEmpty {
                store.add(text: "Call the dentist", dueAt: Calendar.current.date(byAdding: .hour, value: 2, to: Date()), priority: 3)
                store.add(text: "Review Q3 budget", detail: "Focus on the marketing line", startAt: Calendar.current.date(byAdding: .hour, value: 6, to: Date()), dueAt: Calendar.current.date(byAdding: .day, value: 2, to: Date()), priority: 2)
                store.add(text: "Read chapter 4 of the Swift book")
                store.add(text: "Book flights for the trip", dueAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()), priority: 1)
                store.addNote(text: "Shower thought: the RAM metaphor explains why I forget things I can't hold")
                store.addNote(text: "Idea for the essay intro — start with the memory palace")
                store.addNote(text: "Ask Prof. Chen about the deadline extension")
            }
        }
        if env["HRAM_DEBUG_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                CapturePanel.shared.show(mode: .note)
                WindowManager.shared.showDigest()
                WindowManager.shared.showDiary()
                WindowManager.shared.showNotesReview()
                WindowManager.shared.showJournal()
                WindowManager.shared.showSettings()
            }
        }
    }
}