import SwiftUI

public struct EditItemView: View {
    @EnvironmentObject private var store: ItemStore
    let itemID: UUID

    public init(itemID: UUID) {
        self.itemID = itemID
    }

    private enum Field: Hashable { case text, detail, start, due }

    @State private var text = ""
    @State private var detail = ""
    @State private var startAt: Date?
    @State private var due: Date?
    @State private var priority = 2
    @State private var loaded = false
    @FocusState private var focus: Field?

    public var body: some View {
        Group {
            if let item = store.item(id: itemID) {
                form(item)
            } else {
                Text("This item no longer exists.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func form(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Task", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($focus, equals: .text)
                .onSubmit { focus = .start }

            MultilineEditor("Notes", text: $detail, minHeight: 72, bordered: true,
                            focus: $focus, field: .detail)

            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    DateTimeField(date: $startAt, label: "Start", focus: $focus, field: .start, onSubmit: { focus = .due })
                    DateTimeField(date: $due, label: "Due", focus: $focus, field: .due, onSubmit: { save(item) })
                }
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Text("Priority").font(.caption).foregroundStyle(.secondary)
                Spacer()
                PriorityMenu(priority: $priority)
            }

            Divider()

            HStack {
                if item.state == .loaded {
                    Button("Spill to hard drive") {
                        store.spillToDisk(id: item.id)
                    }
                } else if item.state == .backlog {
                    Button("Load into RAM") {
                        store.loadToRAM(id: item.id)
                    }
                }
                Spacer()
                Button("Save", action: { save(item) })
                    .keyboardShortcut(.return, modifiers: .command)
            }

            Text("⏎ next · ⌘⏎ save · ⌘1–4 priority · esc cancel")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .onAppear {
            guard !loaded else { return }
            text = item.text
            detail = item.detail ?? ""
            startAt = item.startAt
            due = item.dueAt
            priority = item.priority
            loaded = true
            focus = .text
        }
        .shortcutActions(
            store: { save(item) },
            cancel: { AppRouter.shared.dismissActiveWindow() }
        )
        .priorityShortcut { priority = $0 }
    }

    private func save(_ item: Item) {
        var updated = item
        updated.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.text.isEmpty { updated.text = "(untitled)" }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.detail = trimmedDetail.isEmpty ? nil : trimmedDetail
        updated.startAt = startAt
        updated.dueAt = due
        updated.priority = priority
        store.update(updated)
        AppRouter.shared.dismissActiveWindow()
    }
}
