import SwiftUI

/// The nightly review: go through captured thoughts one by one.
/// Each one you clear is filed into the journal with a timestamp.
public struct NotesReviewView: View {
    @EnvironmentObject private var store: ItemStore

    @State private var total = 0
    @State private var skipped: Set<UUID> = []
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool?

    public init() {}

    private var pending: [Item] {
        store.notesInbox.filter { !skipped.contains($0.id) }
    }

    private var filed: Int {
        max(0, total - store.inboxCount)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let note = pending.first {
                card(note)
            } else {
                caughtUp
            }
        }
        .onAppear { total = store.inboxCount }
        .onChange(of: pending.first?.id) { _, _ in
            isEditing = false
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tonight's Notes")
                .font(.title2)
                .fontWeight(.semibold)
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 160)
                Text("\(filed) filed · \(pending.count) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
    }

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(filed) / Double(total))
    }

    // MARK: - Card

    private func card(_ note: Item) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .foregroundStyle(.secondary)
                Text("Captured \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if isEditing {
                MultilineEditor("Note", text: $editText, font: .title3, minHeight: 160,
                                focus: $editFocused, field: true)
            } else {
                Text(note.text)
                    .font(.title3)
                    .textSelection(.enabled)
            }
            if let detail = note.detail, !detail.isEmpty, !isEditing {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    if isEditing {
                        saveEdit(note)
                    } else {
                        editText = note.text
                        isEditing = true
                        editFocused = true
                    }
                } label: {
                    Label(isEditing ? "Save edit" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                }

                Button {
                    store.delete(id: note.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(isEditing)

                Spacer()

                Button {
                    skipped.insert(note.id)
                } label: {
                    Label("Later", systemImage: "clock.arrow.circlepath")
                }
                .disabled(isEditing)

                Button {
                    store.noteToTask(id: note.id)
                } label: {
                    Label("Make task", systemImage: "arrow.up.right.square")
                }
                .disabled(isEditing)

                Button {
                    store.journalNote(id: note.id)
                } label: {
                    Label("Journal", systemImage: "book.closed")
                }
                .disabled(isEditing)
                .keyboardShortcut(isEditing ? nil : KeyboardShortcut.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .shortcutActions(
            store: { if isEditing { saveEdit(note) } },
            cancel: { if isEditing { isEditing = false } }
        )
    }

    private func saveEdit(_ note: Item) {
        var updated = note
        updated.text = editText
        store.update(updated)
        isEditing = false
    }

    // MARK: - Empty

    private var caughtUp: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(total == 0 ? "No notes to review" : "All caught up")
                .font(.title3)
            Text(total == 0
                 ? "Capture a note from the capture box and it'll wait here."
                 : "\(filed) filed into your journal.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}