import AppKit
import SwiftUI
import HumanRAMCore

/// Manages the app's secondary windows (digest, diary, settings, edit).
final class WindowManager {
    static let shared = WindowManager()
    private var controllers: [String: NSWindowController] = [:]

    private func show<Content: View>(
        _ id: String,
        title: String,
        size: CGSize,
        resizable: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        NSApp.setActivationPolicy(.accessory)
        if let wc = controllers[id], let window = wc.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = content().environmentObject(ItemStore.shared)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.setContentSize(size)
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        let wc = NSWindowController(window: window)
        controllers[id] = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showDigest() {
        show("digest", title: "Daily Scan", size: CGSize(width: 620, height: 640)) {
            DigestView()
        }
    }

    func showDiary() {
        show("diary", title: "Diary", size: CGSize(width: 720, height: 660)) {
            DiaryView()
        }
    }

    func showNotesReview() {
        show("notes-review", title: "Tonight's Notes", size: CGSize(width: 560, height: 520)) {
            NotesReviewView()
        }
    }

    func showJournal() {
        show("journal", title: "Journal", size: CGSize(width: 720, height: 660)) {
            JournalView()
        }
    }

    func showGuide() {
        show("guide", title: "Welcome to Human RAM", size: CGSize(width: 560, height: 620), resizable: false) {
            GuideView()
        }
    }

    func showSettings() {
        show("settings", title: "Human RAM Settings", size: CGSize(width: 460, height: 520), resizable: false) {
            SettingsView()
        }
    }

    func showEdit(itemID: UUID) {
        show("edit-\(itemID.uuidString)", title: "Edit Item", size: CGSize(width: 440, height: 360)) {
            EditItemView(itemID: itemID)
        }
    }
}