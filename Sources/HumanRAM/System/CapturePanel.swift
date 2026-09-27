import AppKit
import SwiftUI
import HumanRAMCore

/// A panel that intercepts its own key events. App-level local event monitors
/// do not fire while the app is inactive, but a `.nonactivatingPanel` still
/// receives key events, so shortcuts are handled here at the window level.
final class CapturePanelWindow: NSPanel {
    /// Return `true` to consume the event before it reaches the responder chain.
    var onKeyDown: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }
}

/// A floating, panel-based overlay so the capture box appears over any app.
final class CapturePanel {
    static let shared = CapturePanel()
    private var panel: CapturePanelWindow?
    private var model: CaptureModel?

    func toggle(mode: CaptureMode) {
        if let panel, panel.isVisible {
            hide()
        } else {
            show(mode: mode)
        }
    }

    func show(mode: CaptureMode) {
        hide()
        let model = CaptureModel()
        model.prepare(mode: mode)
        model.onDismiss = { [weak self] in self?.hide() }
        self.model = model

        let hosting = NSHostingController(rootView: CaptureView(model: model))
        let panel = CapturePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.center()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        if Shortcuts.isCancel(event) {
            hide()
            return true
        }
        if Shortcuts.isTab(event) {
            model.toggleMode()
            return true
        }
        if Shortcuts.isDetail(event) {
            model.showDetail = true
            model.focus = .detail
            return true
        }
        if Shortcuts.isStore(event) {
            model.submit()
            return true
        }
        if model.mode == .task, let priority = Shortcuts.priority(for: event) {
            model.setPriority(priority)
            return true
        }
        return false
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        model = nil
    }
}
