import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import UserNotifications
import HumanRAMCore

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var scanTime = Date()
    @State private var reviewTime = Date()
    @State private var dataMessage: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var calendarPermission: CalendarSync.Permission = .notDetermined
    @State private var calendars: [CalendarSync.CalendarOption] = []

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var windowLabel: String {
        let hours = settings.ramWindowHours
        if hours % 24 == 0 { return "\(hours / 24) days" }
        return "\(hours) hours"
    }

    var body: some View {
        Form {
            if let quarantined = ItemStore.shared.quarantinedDatabaseURL {
                Section {
                    Label("A damaged database was found and set aside. Human RAM started fresh; the old file is kept below.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Reveal set-aside database") {
                        NSWorkspace.shared.activateFileViewerSelecting([quarantined])
                    }
                }
            }
            if let message = dataMessage {
                Section {
                    Text(message).font(.callout)
                }
            }

            Section("Working memory") {
                Stepper(value: $settings.workingSetLimit, in: 1...50) {
                    LabeledContent("RAM capacity", value: "\(settings.workingSetLimit)")
                }
                .onChange(of: settings.workingSetLimit) { _, _ in
                    ItemStore.shared.enforceCapacity()
                    ItemStore.shared.fillWorkingSet()
                }
                Text("How many items stay loaded at once. Overflow spills to the hard drive.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Auto-arrange") {
                Toggle("Keep RAM relevant", isOn: $settings.autoArrangeEnabled)
                    .onChange(of: settings.autoArrangeEnabled) { _, _ in
                        ItemStore.shared.applyTimeWindow()
                    }
                Stepper(value: $settings.ramWindowHours, in: 1...720) {
                    LabeledContent("Window", value: windowLabel)
                }
                .onChange(of: settings.ramWindowHours) { _, _ in
                    ItemStore.shared.applyTimeWindow()
                }
                Text("A task with a start date spills while it is further out than the window, then loads back as it enters. A task without a start date waits for its priority instead: 3 days before the due date for high, 2 for normal, 1 for low, and the due day for no priority.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Decay") {
                Stepper(value: $settings.decayDimDays, in: 1...60) {
                    LabeledContent("Dim after", value: "\(settings.decayDimDays) days")
                }
                Stepper(value: $settings.decaySpillDays, in: 1...120) {
                    LabeledContent("Spill after", value: "\(settings.decaySpillDays) days")
                }
                Text("Untouched loaded items fade, then spill to the hard drive. Pinned items are safe.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Daily scan") {
                DatePicker("Digest at", selection: $scanTime, displayedComponents: .hourAndMinute)
                    .onChange(of: scanTime) { _, value in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: value)
                        settings.dailyScanHour = c.hour ?? 19
                        settings.dailyScanMinute = c.minute ?? 20
                        NotificationCenter.default.post(name: .humanRAMScheduleChanged, object: nil)
                    }
            }

            Section("Notes") {
                Stepper(value: $settings.noteCapacity, in: 1...100) {
                    LabeledContent("Inbox capacity", value: "\(settings.noteCapacity)")
                }
                Toggle("Nightly review", isOn: $settings.noteReviewEnabled)
                    .onChange(of: settings.noteReviewEnabled) { _, _ in
                        NotificationCenter.default.post(name: .humanRAMScheduleChanged, object: nil)
                    }
                Toggle("Open review on launch", isOn: $settings.noteReviewOnLaunch)
                Text("When off, the review only opens at its scheduled time — not when you launch the app. You can always open it from the menu bar's Review button.")
                    .font(.caption).foregroundStyle(.secondary)
                DatePicker("Review at", selection: $reviewTime, displayedComponents: .hourAndMinute)
                    .onChange(of: reviewTime) { _, value in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: value)
                        settings.noteReviewHour = c.hour ?? 0
                        settings.noteReviewMinute = c.minute ?? 0
                        NotificationCenter.default.post(name: .humanRAMScheduleChanged, object: nil)
                    }
                Text("Captured thoughts wait in the inbox and are filed into the journal during review.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notifications") {
                LabeledContent("Status", value: notificationStatusLabel)
                    .foregroundStyle(notificationStatus == .authorized ? .primary : .secondary)
                switch notificationStatus {
                case .denied:
                    Button("Open Notification Settings…") { openNotificationSettings() }
                case .notDetermined:
                    Button("Enable notifications") {
                        Notifications.shared.requestAuthorization { _ in refreshNotificationStatus() }
                    }
                default:
                    EmptyView()
                }
                Button("Send a test notification") { Notifications.shared.sendTestNotification() }
                Text("Human RAM uses native notifications for due tasks, the Daily Scan, and the nightly review. If none appear, allow Human RAM in System Settings → Notifications, and check that Focus/Do Not Disturb is off.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Calendar") {
                Toggle("Add tasks to Calendar", isOn: $settings.calendarSyncEnabled)
                    .onChange(of: settings.calendarSyncEnabled) { _, enabled in
                        if enabled, calendarPermission == .notDetermined {
                            CalendarSync.shared.requestAccess { _ in refreshCalendar() }
                        }
                        refreshCalendar()
                    }
                switch calendarPermission {
                case .authorized:
                    Picker("Calendar", selection: $settings.calendarIdentifier) {
                        Text("Human RAM (dedicated)").tag("")
                        ForEach(calendars) { calendar in
                            Text(calendar.displayName).tag(calendar.id)
                        }
                    }
                    .disabled(!settings.calendarSyncEnabled)
                case .notDetermined:
                    Button("Allow Calendar Access") {
                        CalendarSync.shared.requestAccess { _ in refreshCalendar() }
                    }
                case .denied:
                    Button("Open Calendar Privacy Settings…") { openCalendarSettings() }
                }
                Text("Mirrors tasks with a start or due time as calendar events, one-way, with an alarm. Because your Mac syncs iCloud/Google/Outlook calendars, those reminders also reach your phone. Events are never edited back into Human RAM.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Capture hotkey") {
                LabeledContent("Shortcut",
                               value: HotKeyDescriptor.string(keyCode: settings.hotkeyKeyCode,
                                                              modifiers: settings.hotkeyModifiers))
                Button("Reset to ⌘⇧N") {
                    settings.hotkeyKeyCode = 45
                    settings.hotkeyModifiers = 0x100 | 0x200
                    NotificationCenter.default.post(name: .humanRAMHotKeyChanged, object: nil)
                }
                Text("Opens as a task. Press Tab in the capture box to switch to a note.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Guide") {
                Toggle("Show guide at startup", isOn: $settings.showGuideOnLaunch)
                Button("Open the guide") { WindowManager.shared.showGuide() }
                Text("A short tour of how Human RAM works. Reopen it here any time.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("System follows your Mac's light/dark setting. Choose Light or Dark to override it for Human RAM only.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, value in
                        LaunchAtLogin.set(enabled: value)
                    }
                LabeledContent("Year", value: "\(settings.year)")
                Stepper("Adjust year", value: $settings.year, in: 2000...2100)
            }

            Section("Your data") {
                Button("Back up the database now") {
                    if let url = ItemStore.shared.backupDatabase(label: "manual") {
                        dataMessage = "Backup saved to \(url.lastPathComponent)."
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        dataMessage = "Could not create a backup."
                    }
                }
                Button("Show database in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ItemStore.shared.databaseURL])
                }
                Button("Show backups folder") {
                    let dir = ItemStore.shared.databaseURL
                        .deletingLastPathComponent()
                        .appendingPathComponent("Backups", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                Button("Export everything…") { exportArchive() }
                Button("Import from an export…") { importArchive() }
                Text("Human RAM is fully offline. Back up or export before big changes; importing merges by item and keeps the newest edit.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                if let release = updates.available {
                    Button("Version \(release.version) is available") {
                        NSWorkspace.shared.open(release.url)
                    }
                    .foregroundStyle(.blue)
                } else {
                    Button(updates.isChecking ? "Checking…" : "Check for updates now") {
                        updates.check()
                    }
                    .disabled(updates.isChecking)
                }
                Text("Uses one anonymous request to the public GitHub Releases page. No account, no tracking, no data leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Developer", value: "Derek Han")
                Text("Human RAM — your attention, treated like memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = settings.dailyScanHour
            comps.minute = settings.dailyScanMinute
            scanTime = Calendar.current.date(from: comps) ?? Date()
            var rcomps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            rcomps.hour = settings.noteReviewHour
            rcomps.minute = settings.noteReviewMinute
            reviewTime = Calendar.current.date(from: rcomps) ?? Date()
            updates.checkIfEnabled()
            refreshNotificationStatus()
            refreshCalendar()
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .provisional: return "Quiet"
        case .ephemeral: return "Temporary"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private func refreshNotificationStatus() {
        Notifications.shared.authorizationStatus { notificationStatus = $0 }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshCalendar() {
        calendarPermission = CalendarSync.shared.permission()
        calendars = CalendarSync.shared.availableCalendars()
    }

    private func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportArchive() {
        let panel = NSSavePanel()
        panel.title = "Export Human RAM data"
        panel.nameFieldStringValue = "humanram-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ItemStore.shared.exportArchiveData()
            try data.write(to: url, options: .atomic)
            dataMessage = "Exported \(ItemStore.shared.items.count) items to \(url.lastPathComponent)."
        } catch {
            dataMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importArchive() {
        let panel = NSOpenPanel()
        panel.title = "Import Human RAM data"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let count = try ItemStore.shared.importArchive(data)
            dataMessage = count > 0
                ? "Imported or updated \(count) items."
                : "Nothing to import — your data was already up to date."
        } catch {
            dataMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

enum LaunchAtLogin {
    static func set(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("HumanRAM launch-at-login error: \(error.localizedDescription)")
        }
    }
}