import SwiftUI
#if os(macOS)
import AppKit
#endif

public enum Shortcuts {
    public static let returnKeyCode: UInt16 = 36
    public static let tabKeyCode: UInt16 = 48
    public static let escapeKeyCode: UInt16 = 53

    static var priorityCount: Int { PriorityMenu.labels.count }

    #if os(macOS)
    private static func flags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    public static func priority(for event: NSEvent) -> Int? {
        guard flags(event).contains(.command),
              let characters = event.charactersIgnoringModifiers,
              let number = Int(characters),
              (1...priorityCount).contains(number) else { return nil }
        return number - 1
    }

    public static func isStore(_ event: NSEvent) -> Bool {
        event.keyCode == returnKeyCode && flags(event).contains(.command)
    }

    public static func isDetail(_ event: NSEvent) -> Bool {
        event.keyCode == returnKeyCode && flags(event).contains(.option)
    }

    public static func isTab(_ event: NSEvent) -> Bool {
        event.keyCode == tabKeyCode
    }

    public static func isCancel(_ event: NSEvent) -> Bool {
        event.keyCode == escapeKeyCode
    }
    #endif
}

#if os(macOS)
/// Reports the hosting window the moment the view lands in it. `updateNSView`
/// alone is unreliable for panels that host a view without further updates.
private final class WindowReportingView: NSView {
    var onWindow: ((NSWindow?) -> Void)?
    private weak var reported: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    func report() {
        guard window !== reported else { return }
        reported = window
        onWindow?(window)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
        nsView.report()
    }
}

private struct ShortcutActions: ViewModifier {
    var onStore: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDetail: (() -> Void)?

    @State private var monitor: Any?
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor { window = $0 })
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard let window, event.window === window else { return event }
                    if let onCancel, Shortcuts.isCancel(event) {
                        onCancel()
                        return nil
                    }
                    if let onStore, Shortcuts.isStore(event) {
                        onStore()
                        return nil
                    }
                    if let onDetail, Shortcuts.isDetail(event) {
                        onDetail()
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

/// Applies `⌘1`–`⌘4` priority changes broadcast by the app-level monitor in
/// `AppDelegate`. Scoping by window keeps a background editor from reacting.
private struct PriorityShortcutModifier: ViewModifier {
    var onPriority: (Int) -> Void
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor { window = $0 })
            .onReceive(NotificationCenter.default.publisher(for: .humanRAMSetPriority)) { note in
                guard let priority = note.userInfo?[HumanRAMNotificationKey.priority] as? Int else { return }
                if let window {
                    if let target = note.object as? NSWindow {
                        guard window === target else { return }
                    } else {
                        guard window === NSApp.keyWindow else { return }
                    }
                }
                onPriority(priority)
            }
    }
}
#endif

extension View {
    public func shortcutActions(
        store: (() -> Void)? = nil,
        cancel: (() -> Void)? = nil,
        detail: (() -> Void)? = nil
    ) -> some View {
        #if os(macOS)
        modifier(ShortcutActions(onStore: store, onCancel: cancel, onDetail: detail))
        #else
        self
        #endif
    }

    /// Handles `⌘1`–`⌘4` priority changes without requiring the priority menu.
    public func priorityShortcut(_ onPriority: @escaping (Int) -> Void) -> some View {
        #if os(macOS)
        modifier(PriorityShortcutModifier(onPriority: onPriority))
        #else
        self
        #endif
    }
}
