import AppKit
import SwiftUI
import HumanRAMCore

/// Debug-only screenshot pass. When `HRAM_SNAPSHOT_DIR` is set, the app renders
/// each of its windows to a PNG in that folder and quits. It captures its own
/// content view, so it needs no Screen Recording permission.
enum SnapshotService {
    @discardableResult
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["HRAM_SNAPSHOT_DIR"] else { return false }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            var steps: [(String, () -> NSWindow?)] = []
            steps.append(("menu-bar", { standalone(MenuBarView().environmentObject(ItemStore.shared), size: CGSize(width: 440, height: 620)) }))
            steps.append(("capture", {
                CapturePanel.shared.show(mode: .task)
                return NSApp.windows.first { $0 is CapturePanelWindow }
            }))
            steps.append(("daily-scan", { WindowManager.shared.showDigest(); return window(titled: "Daily Scan") }))
            steps.append(("settings", { WindowManager.shared.showSettings(); return window(titled: "Human RAM Settings") }))
            steps.append(("notes-review", { WindowManager.shared.showNotesReview(); return window(titled: "Tonight's Notes") }))
            steps.append(("diary", { WindowManager.shared.showDiary(); return window(titled: "Diary") }))
            steps.append(("guide", { WindowManager.shared.showGuide(); return window(titled: "Welcome to Human RAM") }))
            run(steps: steps, dir: dir)
        }
        return true
    }

    private static func run(steps: [(String, () -> NSWindow?)], dir: URL, index: Int = 0) {
        guard index < steps.count else {
            NSApp.terminate(nil)
            return
        }
        let (name, setup) = steps[index]
        let target = setup()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            snapshot(target, name: name, into: dir)
            target?.orderOut(nil)
            run(steps: steps, dir: dir, index: index + 1)
        }
    }

    private static func standalone<V: View>(_ view: V, size: CGSize) -> NSWindow {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled]
        window.setContentSize(size)
        window.center()
        window.orderFront(nil)
        return window
    }

    private static func window(titled title: String) -> NSWindow? {
        NSApp.windows.first { $0.title == title }
    }

    private static func snapshot(_ window: NSWindow?, name: String, into dir: URL) {
        guard let window, let view = window.contentView else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let scale = window.backingScaleFactor
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
