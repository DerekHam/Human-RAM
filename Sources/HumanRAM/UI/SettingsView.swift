import SwiftUI
import ServiceManagement
import HumanRAMCore

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var scanTime = Date()
    @State private var reviewTime = Date()

    private var windowLabel: String {
        let hours = settings.ramWindowHours
        if hours % 24 == 0 { return "\(hours / 24) days" }
        return "\(hours) hours"
    }

    var body: some View {
        Form {
            Section("Working memory") {
                Stepper(value: $settings.workingSetLimit, in: 1...50) {
                    LabeledContent("RAM capacity", value: "\(settings.workingSetLimit)")
                }
                .onChange(of: settings.workingSetLimit) { _, _ in
                    ItemStore.shared.enforceCapacity()
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
                Text("Tasks whose start (or due) is further out than the window spill to the hard drive; tasks entering the window load into RAM automatically.")
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

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, value in
                        LaunchAtLogin.set(enabled: value)
                    }
                LabeledContent("Year", value: "\(settings.year)")
                Stepper("Adjust year", value: $settings.year, in: 2000...2100)
            }

            Section("About") {
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