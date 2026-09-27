import SwiftUI
import AppKit
import HumanRAMCore

struct MenuBarView: View {
    @EnvironmentObject private var store: ItemStore
    @ObservedObject private var settings = AppSettings.shared

    private enum QuickField: Hashable { case start, due }

    @State private var quickMode: CaptureMode = .task
    @State private var quickText = ""
    @State private var quickStartAt: Date?
    @State private var quickDue: Date?
    @State private var quickPriority = 2
    @State private var showBacklog = false
    @FocusState private var quickFocused: Bool?
    @FocusState private var quickField: QuickField?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickCapture
            Divider()
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 380)
        .priorityShortcut { if quickMode == .task { quickPriority = $0 } }
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
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Open the floating capture window")
            }

            HStack(alignment: .bottom, spacing: 8) {
                quickInput
                Button(action: addQuick) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Store (⌘⏎)")
                .disabled(quickText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if quickMode == .task {
                HStack(alignment: .top, spacing: 12) {
                    DateTimeField(date: $quickStartAt, label: "Start", focus: $quickField, field: .start, onSubmit: { quickField = .due })
                    DateTimeField(date: $quickDue, label: "Due", focus: $quickField, field: .due, onSubmit: addQuick)
                }
                HStack {
                    Spacer()
                    PriorityMenu(priority: $quickPriority)
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
                .focused($quickFocused, equals: true)
                .onSubmit { addQuick() }
        } else {
            MultilineEditor("Jot a note…", text: $quickText, minHeight: 60, bordered: true,
                            focus: $quickFocused, field: true)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if store.loaded.isEmpty {
                    emptyState
                } else {
                    sectionTitle("Loaded", count: store.loaded.count)
                    ForEach(store.loaded) { item in
                        ItemRow(item: item)
                    }
                }

                if !store.backlog.isEmpty {
                    Divider().padding(.vertical, 4)
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

                notesSection
            }
        }
        .frame(maxHeight: 380)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
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
                ForEach(store.notesInbox.prefix(4)) { note in
                    NoteRow(note: note)
                }
                if store.inboxCount > 4 {
                    Text("+\(store.inboxCount - 4) more…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RAM is empty")
                .font(.subheadline)
            Text("Hit \(HotKeyDescriptor.string(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)) to capture anything.")
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
        HStack(spacing: 12) {
            Button { WindowManager.shared.showDigest() } label: {
                Label("Scan", systemImage: "sun.max")
            }
            .buttonStyle(.borderless)
            Button { WindowManager.shared.showDiary() } label: {
                Label("Diary", systemImage: "book")
            }
            .buttonStyle(.borderless)
            Button { WindowManager.shared.showJournal() } label: {
                Label("Journal", systemImage: "brain")
            }
            .buttonStyle(.borderless)
            Button { WindowManager.shared.showSettings() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .labelStyle(.titleAndIcon)
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
        quickFocused = true
    }
}

// MARK: - Row

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
                if let start = item.startAt, item.hasUpcomingStart {
                    StartChip(date: start)
                }
                if let due = item.dueAt {
                    DueChip(date: due)
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
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "circle.dashed")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.text).lineLimit(2)
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Journal it") { store.journalNote(id: note.id) }
            Button("Make into a task") { store.noteToTask(id: note.id) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(id: note.id) }
        }
    }
}