import SwiftUI
import AppKit
import HumanRAMCore

struct MenuBarView: View {
    @EnvironmentObject private var store: ItemStore
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateChecker.shared

    private enum QuickField: Hashable { case text, start, due }

    @State private var quickMode: CaptureMode = .task
    @State private var quickText = ""
    @State private var quickStartAt: Date?
    @State private var quickDue: Date?
    @State private var quickPriority = 2
    @State private var showBacklog = false
    @State private var lowerContentHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @FocusState private var quickField: QuickField?

    private let menuWidth: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let release = updates.available {
                updateBanner(release)
            }
            quickCapture
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Divider()
            content
            Divider()
            footer
        }
        .padding(10)
        .frame(width: menuWidth)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
        .background(WindowSizer(width: menuWidth, height: contentHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onWindow { window in
            // MenuBarExtra's window is non-activating; without this the app-level
            // key monitors (Tab/shortcuts) never see events from it.
            HumanRAMWindows.menuBar = window
            guard window != nil, !NSApp.isActive else { return }
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .humanRAMToggleCaptureMode)) { _ in
            toggleQuickMode()
        }
        .priorityShortcut { if quickMode == .task { quickPriority = $0 } }
    }

    private func toggleQuickMode() {
        quickMode = quickMode == .task ? .note : .task
        quickField = .text
    }

    private var captureKey: String {
        HotKeyDescriptor.string(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private var hint: String {
        quickMode == .task
            ? "\(captureKey) capture · ⇥ note · ⏎ next · ⌘⏎ store · ⌘1–4 priority"
            : "\(captureKey) capture · ⇥ task · ⏎ new line · ⌘⏎ store"
    }

    /// How tall the scrollable backlog/notes area may grow, clamped to the
    /// available screen so the dropdown never runs off the bottom.
    private var lowerMaxHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(180, min(360, visible - 430))
    }

    private var noteColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10, alignment: .leading),
         GridItem(.flexible(), spacing: 10, alignment: .leading)]
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Label("Human RAM", systemImage: "memorychip")
                .font(.headline)
            Spacer()
            Text("\(store.loaded.count)/\(settings.workingSetLimit) in RAM")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func updateBanner(_ release: ReleaseInfo) -> some View {
        Button {
            NSWorkspace.shared.open(release.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("Human RAM \(release.version) is available")
                    .font(.caption).fontWeight(.medium)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Open the release page to download the update")
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $quickMode) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)

                Spacer()

                Button { CapturePanel.shared.show(mode: quickMode) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text(captureKey).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.borderless)
                .help("Open the floating capture window (\(captureKey))")
            }

            HStack(alignment: .bottom, spacing: 8) {
                quickInput
                Button(action: addQuick) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("⌘⏎").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Store (⌘⏎)")
                .disabled(quickText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if quickMode == .task {
                HStack(alignment: .center, spacing: 8) {
                    DateTimeField(date: $quickStartAt, placeholder: "MMDD", label: "Start", compact: true, focus: $quickField, field: .start, onSubmit: { quickField = .due })
                    DateTimeField(date: $quickDue, placeholder: "MMDD", label: "Due", compact: true, focus: $quickField, field: .due, onSubmit: addQuick)
                    Spacer(minLength: 0)
                    PriorityMenu(priority: $quickPriority, showsShortcut: true)
                }
            }
        }
    }

    @ViewBuilder
    private var quickInput: some View {
        if quickMode == .task {
            TextField("Quick write to RAM…", text: $quickText)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .focused($quickField, equals: .text)
                .onSubmit { quickField = .start }
        } else {
            MultilineEditor("Jot a note…", text: $quickText, minHeight: 60, bordered: true,
                            focus: $quickField, field: .text)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.loaded.isEmpty {
                emptyState
            } else {
                sectionTitle("Loaded", count: store.loaded.count)
                ForEach(store.loaded) { item in
                    ItemRow(item: item)
                }
            }

            Divider().padding(.vertical, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    backlogSection
                    notesSection
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: LowerHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .frame(height: min(max(lowerContentHeight, 1), lowerMaxHeight))
            .onPreferenceChange(LowerHeightKey.self) { lowerContentHeight = $0 }
        }
    }

    @ViewBuilder
    private var backlogSection: some View {
        if !store.backlog.isEmpty {
            DisclosureGroup(isExpanded: $showBacklog) {
                ForEach(store.backlog) { item in
                    ItemRow(item: item)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive")
                    Text("Hard drive")
                    Text("\(store.backlog.count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                Text("NOTES")
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                Text("\(store.inboxCount)/\(settings.noteCapacity)")
                    .font(.caption2)
                    .foregroundStyle(store.isInboxFull ? .red : .secondary)
                if store.isInboxFull {
                    Text("FULL")
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.red.opacity(0.18), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Review") { WindowManager.shared.showNotesReview() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            if store.notesInbox.isEmpty {
                Text("No thoughts waiting.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: noteColumns, alignment: .leading, spacing: 4) {
                    ForEach(store.notesInbox.prefix(6)) { note in
                        NoteRow(note: note)
                    }
                }
                if store.inboxCount > 6 {
                    Text("+\(store.inboxCount - 6) more…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RAM is empty")
                .font(.subheadline)
            Text("Hit \(captureKey) to capture anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(text.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            footerButton("Scan", systemImage: "sun.max", key: "⌘D", shortcut: KeyEquivalent("d")) {
                WindowManager.shared.showDigest()
            }
            footerButton("Diary", systemImage: "book", key: "⌘Y", shortcut: KeyEquivalent("y")) {
                WindowManager.shared.showDiary()
            }
            footerButton("Journal", systemImage: "brain", key: "⌘J", shortcut: KeyEquivalent("j")) {
                WindowManager.shared.showJournal()
            }
            footerButton("Settings", systemImage: "gearshape", key: "⌘,", shortcut: KeyEquivalent(",")) {
                WindowManager.shared.showSettings()
            }
            Spacer(minLength: 0)
            footerButton(nil, systemImage: "power", key: "⌘Q", shortcut: KeyEquivalent("q")) {
                NSApp.terminate(nil)
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    private func footerButton(
        _ title: String?,
        systemImage: String,
        key: String,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let title {
                    Label(title, systemImage: systemImage)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Image(systemName: systemImage)
                }
                Text(key)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(shortcut, modifiers: .command)
        .help(title.map { "\($0) (\(key))" } ?? "Quit (\(key))")
    }

    private func addQuick() {
        let trimmed = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch quickMode {
        case .task:
            store.add(text: trimmed, startAt: quickStartAt, dueAt: quickDue, priority: quickPriority)
        case .note:
            store.addNote(text: trimmed)
        }
        quickText = ""
        quickStartAt = nil
        quickDue = nil
        quickPriority = 2
        quickField = .text
    }
}

// MARK: - Row

private struct LowerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// `MenuBarExtra` never resizes its panel when the SwiftUI content changes
/// height, so the content shrinks inside an oversized window. This reads the
/// measured height and resizes the hosting window to match, keeping the top
/// left corner (the menu-bar anchor) fixed.
private struct WindowSizer: NSViewRepresentable {
    var width: CGFloat
    var height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard height > 1, let window = nsView.window else { return }
            let target = NSSize(width: width, height: height)
            guard window.contentView?.frame.size != target else { return }
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(target)
            var frame = window.frame
            frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
            window.setFrame(frame, display: true)
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject private var store: ItemStore
    @ObservedObject private var settings = AppSettings.shared
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                store.complete(id: item.id)
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Mark done")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if item.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    if item.priority == 3 {
                        Image(systemName: "exclamationmark.2").font(.caption2).foregroundStyle(.red)
                    }
                    Text(item.text)
                }
                if (item.startAt != nil && item.hasUpcomingStart) || item.dueAt != nil {
                    HStack(spacing: 4) {
                        if let start = item.startAt, item.hasUpcomingStart {
                            StartChip(date: start)
                        }
                        if let due = item.dueAt {
                            DueChip(date: due)
                        }
                    }
                }
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .opacity(rowOpacity)
        .contentShape(Rectangle())
        .contextMenu { menu }
    }

    private var rowOpacity: Double {
        guard item.state == .loaded else { return 1 }
        let f = item.freshness(decayDimDays: settings.decayDimDays)
        return 0.55 + 0.45 * f
    }

    @ViewBuilder
    private var menu: some View {
        Button("Mark done") { store.complete(id: item.id) }
        Button("Edit…") { WindowManager.shared.showEdit(itemID: item.id) }
        Divider()
        if item.state == .loaded {
            Button("Spill to hard drive") { store.spillToDisk(id: item.id) }
        } else if item.state == .backlog {
            Button("Load into RAM") { store.loadToRAM(id: item.id) }
        }
        Button(item.pinned ? "Unpin" : "Pin to RAM") { store.togglePin(id: item.id) }
        Menu("Priority") {
            ForEach(Array(PriorityMenu.labels.enumerated()), id: \.offset) { index, label in
                Button {
                    store.setPriority(id: item.id, index)
                } label: {
                    if item.priority == index { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(id: item.id) }
    }
}

struct NoteRow: View {
    @EnvironmentObject private var store: ItemStore
    let note: Item

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.dashed")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(note.text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .help(note.text)
        .contextMenu {
            Button("Journal it") { store.journalNote(id: note.id) }
            Button("Make into a task") { store.noteToTask(id: note.id) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(id: note.id) }
        }
    }
}