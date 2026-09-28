import SwiftUI
import AppKit
import HumanRAMCore

struct GuideView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var window: NSWindow?

    private var taskHotkey: String {
        HotKeyDescriptor.string(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private var windowLabel: String {
        let hours = settings.ramWindowHours
        if hours % 24 == 0 { return "\(hours / 24) days" }
        return "\(hours) hours"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    ideaSection
                    kindsSection
                    captureSection
                    loopSection
                    destinationsSection
                    privacySection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .onWindow { window = $0 }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "memorychip.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Human RAM").font(.largeTitle).fontWeight(.semibold)
                Text("Your attention, treated like memory.")
                    .font(.title3).foregroundStyle(.secondary)
                Text("by Derek Han")
                    .font(.caption).foregroundStyle(.tertiary)
                Text("Early preview — still under development")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var ideaSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("The idea", icon: "lightbulb")
                Text("Your mind holds only a few things at once. Human RAM keeps a small, always-visible working set and quietly moves everything else to storage until it matters again. Capture a thought in one keystroke and let the app decide when it returns.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var kindsSection: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Two kinds of things", icon: "square.on.square")
                HStack(alignment: .top, spacing: 16) {
                    kindColumn(icon: "checkmark.circle", title: "Tasks", tint: .blue,
                               body: "Executable memory. They load into RAM, spill to the hard drive, and finish in the Diary.")
                    kindColumn(icon: "brain", title: "Notes", tint: .purple,
                               body: "Volatile thoughts. They wait in the inbox and are filed into the Journal during review.")
                }
            }
        }
    }

    private var captureSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Capturing", icon: "keyboard")
                shortcutRow("Capture a task", taskHotkey)
                shortcutRow("Capture a note", "\(taskHotkey), then Tab")
                shortcutRow("Store a task", "⏎ walks text → start → due")
                shortcutRow("Store a note", "⌘⏎")
                shortcutRow("Set priority", "⌘1 – ⌘4")
                shortcutRow("Cancel", "Esc")
            }
        }
    }

    private var loopSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("The daily loop", icon: "arrow.triangle.2.circlepath")
                Text("RAM holds \(settings.workingSetLimit) items. Anything beyond that, or scheduled further out than \(windowLabel), spills to the hard drive. The Daily Scan pulls the right things back; the nightly review files your notes.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var destinationsSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Finding your way around", icon: "menubar.rectangle")
                destinationRow("memorychip", "The menu bar icon opens the working set, the hard drive, and your notes.")
                destinationRow("sun.max", "Scan — today's plan, overdue, upcoming, and the hard drive.")
                destinationRow("book", "Diary — everything you've finished, by day.")
                destinationRow("brain", "Journal — every note you've filed.")
                destinationRow("gearshape", "Settings — capacity, schedule, and hotkeys.")
            }
        }
    }

    private var privacySection: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Your data", icon: "lock")
                Text("Human RAM runs entirely offline. There is no account, no sync, no cloud. Everything stays on this Mac:")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("~/Library/Application Support/\(AppVariant.storageFolderName)/humanram.sqlite3")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Show this guide at startup", isOn: $settings.showGuideOnLaunch)
                .toggleStyle(.checkbox)
            Spacer()
            Button("Got it") { window?.close() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.headline)
    }

    private func shortcutRow(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(keys)
                .font(.system(.callout, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .font(.callout)
    }

    private func destinationRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func kindColumn(icon: String, title: String, tint: Color, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(tint)
            Text(body)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
