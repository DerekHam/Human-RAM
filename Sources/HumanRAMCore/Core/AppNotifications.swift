import Foundation

public extension Notification.Name {
    static let humanRAMHotKeyChanged = Notification.Name("humanRAMHotKeyChanged")
    static let humanRAMScheduleChanged = Notification.Name("humanRAMScheduleChanged")

    /// Posted by the app-level key monitor when a priority shortcut (`⌘1`–`⌘4`)
    /// fires. `object` is the target `NSWindow` so only its editing surface reacts.
    static let humanRAMSetPriority = Notification.Name("humanRAMSetPriority")

    /// Posted by the app-level key monitor when Tab fires in the menu-bar
    /// window, to switch the capture mode between task and note.
    static let humanRAMToggleCaptureMode = Notification.Name("humanRAMToggleCaptureMode")
}

public enum HumanRAMNotificationKey {
    public static let priority = "priority"
}
