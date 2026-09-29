import AppKit
import SwiftUI
import HumanRAMCore

/// Debug-only screenshot pass. When `HRAM_SNAPSHOT_DIR` is set, the app renders
/// each of its windows to an opaque PNG in that folder and quits. It captures
/// its own content view, so it needs no Screen Recording permission.
///
/// `HRAM_SNAPSHOT_APPEARANCE` forces `light` or `dark`; when unset the app's
/// current theme is used. `HRAM_SNAPSHOT_SUFFIX` is appended to each file name,
/// so the caller can produce theme-matched sets (see `Scripts/screenshots.sh`).
enum SnapshotService {
    @discardableResult
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["HRAM_SNAPSHOT_DIR"] else { return false }
        let env = ProcessInfo.processInfo.environment
        let suffix = env["HRAM_SNAPSHOT_SUFFIX"] ?? ""
        let appearanceName: NSAppearance.Name? = {
            switch env["HRAM_SNAPSHOT_APPEARANCE"] {
            case "dark": return .darkAqua
            case "light": return .aqua
            default: return nil
            }
        }()
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let appearanceName { NSApp.appearance = NSAppearance(named: appearanceName) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let steps: [(String, () -> NSWindow?)] = [
                ("menu-bar", { standalone(MenuBarView().environmentObject(ItemStore.shared), size: CGSize(width: 440, height: 620)) }),
                ("capture", {
                    CapturePanel.shared.show(mode: .task)
                    return NSApp.windows.first { $0 is CapturePanelWindow }
                }),
                ("daily-scan", { WindowManager.shared.showDigest(); return window(titled: "Daily Scan") }),
                ("settings", { WindowManager.shared.showSettings(); return window(titled: "Human RAM Settings") }),
                ("notes-review", { WindowManager.shared.showNotesReview(); return window(titled: "Tonight's Notes") }),
                ("diary", { WindowManager.shared.showDiary(); return window(titled: "Diary") }),
                ("guide", { WindowManager.shared.showGuide(); return window(titled: "Welcome to Human RAM") }),
            ]
            run(steps: steps, dir: dir, suffix: suffix, appearanceName: appearanceName)
        }
        return true
    }

    private static func run(
        steps: [(String, () -> NSWindow?)],
        dir: URL,
        suffix: String,
        appearanceName: NSAppearance.Name?,
        index: Int = 0
    ) {
        guard index < steps.count else {
            NSApp.terminate(nil)
            return
        }
        let (name, setup) = steps[index]
        let target = setup()
        if let appearanceName { target?.appearance = NSAppearance(named: appearanceName) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            snapshot(target, name: name, suffix: suffix, appearanceName: appearanceName, into: dir)
            target?.orderOut(nil)
            run(steps: steps, dir: dir, suffix: suffix, appearanceName: appearanceName, index: index + 1)
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

    private static func isDark(_ appearanceName: NSAppearance.Name?) -> Bool {
        if let appearanceName { return appearanceName == .darkAqua }
        return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func snapshot(
        _ window: NSWindow?,
        name: String,
        suffix: String,
        appearanceName: NSAppearance.Name?,
        into dir: URL
    ) {
        guard let window, let view = window.contentView else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Render the view on its own; it may contain transparency.
        guard let viewRep = bitmap(size: bounds.size, scale: window.backingScaleFactor) else { return }
        viewRep.size = bounds.size
        view.cacheDisplay(in: bounds, to: viewRep)

        // Composite over an opaque window background so the PNG stays readable
        // on any theme (GitHub dark mode, etc.). Explicit colors, because the
        // dynamic system color does not resolve under a forced appearance. The
        // bitmap context is in pixels, so fill and draw over the full extent.
        let background: NSColor = isDark(appearanceName)
            ? NSColor(calibratedWhite: 0.12, alpha: 1)
            : NSColor(calibratedWhite: 0.93, alpha: 1)
        guard let finalRep = bitmap(size: bounds.size, scale: window.backingScaleFactor),
              let context = NSGraphicsContext(bitmapImageRep: finalRep) else { return }
        let pixels = CGRect(x: 0, y: 0,
                            width: CGFloat(finalRep.pixelsWide),
                            height: CGFloat(finalRep.pixelsHigh))
        context.cgContext.setFillColor((background.usingColorSpace(.deviceRGB) ?? .white).cgColor)
        context.cgContext.fill(pixels)
        if let viewImage = viewRep.cgImage {
            context.cgContext.draw(viewImage, in: pixels)
        }

        guard let data = finalRep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: dir.appendingPathComponent("\(name)\(suffix).png"))
    }

    private static func bitmap(size: CGSize, scale: CGFloat) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    }
}
