import AppKit
import HumanRAMCore

/// Applies the user's appearance choice app-wide. Setting `NSApp.appearance`
/// covers every window the app owns, including the menu-bar popover, the
/// capture panel, and secondary windows.
enum AppAppearanceController {
    static func apply(_ appearance: AppAppearance) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
