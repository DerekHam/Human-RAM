import SwiftUI

public enum CaptureMode: String, CaseIterable {
    case task
    case note

    public var label: String { self == .task ? "Task" : "Note" }
}

/// Focusable fields in the capture overlay, so Enter can walk
/// content → date → complete and the panel can steer focus for ⌥⏎.
public enum CaptureField: Hashable {
    case text
    case detail
    case start
    case due
}

/// Shared state for the capture overlay, owned by CapturePanel so global key
/// handling (tab / esc / ⏎ / ⌘1–4) can drive the SwiftUI view.
public final class CaptureModel: ObservableObject {
    @Published public var mode: CaptureMode = .task
    @Published public var text = ""
    @Published public var detail = ""
    @Published public var startAt: Date?
    @Published public var due: Date?
    @Published public var priority = 2
    @Published public var showDetail = false
    @Published public var focus: CaptureField? = .text

    public var onDismiss: () -> Void = {}

    public init() {}

    public func prepare(mode: CaptureMode) {
        self.mode = mode
        text = ""
        detail = ""
        startAt = nil
        due = nil
        priority = 2
        showDetail = false
        focus = .text
    }

    public func toggleMode() {
        mode = mode == .task ? .note : .task
        focus = .text
    }

    public func setPriority(_ p: Int) {
        priority = max(0, min(PriorityMenu.labels.count - 1, p))
    }

    public func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { onDismiss(); return }
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailOrNil = d.isEmpty ? nil : d
        switch mode {
        case .task:
            ItemStore.shared.add(text: trimmed, detail: detailOrNil, startAt: startAt, dueAt: due, priority: priority)
        case .note:
            ItemStore.shared.addNote(text: trimmed, detail: detailOrNil)
        }
        onDismiss()
    }
}

/// The one-line "write to RAM / jot a note" overlay, shown by the global hotkeys.
public struct CaptureView: View {
    @ObservedObject public var model: CaptureModel
    @FocusState private var focus: CaptureField?

    public init(model: CaptureModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("", selection: $model.mode) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                Spacer()
                Text(model.mode == .task ? "Goes into RAM" : "Goes to your notes inbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.mode == .task {
                TextField("Write to RAM…", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focus, equals: .text)
                    .onSubmit { model.focus = .start }
            } else {
                MultilineEditor("Jot a note…", text: $model.text, font: .title3, minHeight: 72,
                                focus: $focus, field: .text)
            }

            if model.showDetail {
                MultilineEditor("Notes (optional)", text: $model.detail, font: .callout, minHeight: 48,
                                focus: $focus, field: .detail)
            }

            Divider()

            if model.mode == .task {
                HStack(alignment: .top, spacing: 16) {
                    DateTimeField(date: $model.startAt, label: "Start", focus: $focus, field: .start, onSubmit: { model.focus = .due })
                    DateTimeField(date: $model.due, label: "Due", focus: $focus, field: .due, onSubmit: { model.submit() })
                }
            }

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                if model.mode == .task {
                    PriorityMenu(priority: $model.priority)
                }
                Button("Store") { model.submit() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 480)
        .onAppear { focus = .text }
        .onChange(of: model.focus) { _, new in if let new { focus = new } }
        .onChange(of: focus) { _, new in model.focus = new }
    }

    private var hint: String {
        model.mode == .task
            ? "⏎ start → due · ⌘⏎ store · ⌥⏎ notes · ⌘1–4 priority · ⇥ note · esc cancel"
            : "⏎ new line · ⌘⏎ store · ⌥⏎ notes · ⇥ task · esc cancel"
    }
}

/// Small priority control, shared by the capture overlay and item editor.
/// ⌘1–⌘4 map to None/Low/Normal/High.
public struct PriorityMenu: View {
    @Binding public var priority: Int
    var showsShortcut: Bool

    public init(priority: Binding<Int>, showsShortcut: Bool = false) {
        self._priority = priority
        self.showsShortcut = showsShortcut
    }

    public var body: some View {
        Menu {
            ForEach(Array(Self.labels.enumerated()), id: \.offset) { index, label in
                Button {
                    priority = index
                } label: {
                    if priority == index { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        } label: {
            HStack(spacing: 4) {
                Label(Self.labels[priority], systemImage: "flag")
                if showsShortcut {
                    Text("⌘\(priority + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    public static let labels = ["None", "Low", "Normal", "High"]
}
