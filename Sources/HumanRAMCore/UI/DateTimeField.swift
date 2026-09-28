import SwiftUI

/// A compact due-date control.
///
/// Typing reads numbers in `MM/DD/HH/MM` (24 h) order, separators optional and
/// ignored. A small calendar popover allows point-and-click selection, and the
/// year lives in a separate stepper that the numeric entry never disturbs.
public struct DateTimeField<F: Hashable>: View {
    @Binding var date: Date?

    var placeholder: String = "MMDDHHMM"
    var label: String? = nil
    var compact: Bool = false
    var focus: FocusState<F?>.Binding
    var field: F
    var onSubmit: () -> Void = {}

    @State private var raw: String = ""
    @State private var showPicker = false
    @State private var pickerDate = Date()
    @State private var year = AppSettings.shared.year

    public init(
        date: Binding<Date?>,
        placeholder: String = "MMDDHHMM",
        label: String? = nil,
        compact: Bool = false,
        focus: FocusState<F?>.Binding,
        field: F,
        onSubmit: @escaping () -> Void = {}
    ) {
        self._date = date
        self.placeholder = placeholder
        self.label = label
        self.compact = compact
        self.focus = focus
        self.field = field
        self.onSubmit = onSubmit
    }

    public var body: some View {
        Group {
            if compact {
                fieldRow
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let label {
                        Text(label.uppercased())
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    fieldRow
                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(isValid ? Color.secondary : Color.red)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private var fieldRow: some View {
        HStack(spacing: compact ? 3 : 6) {
            if compact, let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "calendar")
                .font(compact ? .caption2 : .body)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $raw)
                .textFieldStyle(.plain)
                .font(.system(compact ? .caption : .body, design: .monospaced))
                .frame(width: compact ? 52 : nil)
                .foregroundStyle(compact && !raw.isEmpty && !isValid ? Color.red : Color.primary)
                .focused(focus, equals: field)
                .onChange(of: raw) { _, newValue in
                    let clean = NumericDateParser.sanitize(newValue)
                    if clean != newValue { raw = clean }
                    liveCommit()
                }
                .onSubmit {
                    commit()
                    onSubmit()
                }
            if date != nil {
                Button { clear() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            Button { showPicker.toggle() } label: {
                Image(systemName: "calendar.badge.clock")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) { pickerView }
        }
    }

    // MARK: - Popover

    private var pickerView: some View {
        VStack(spacing: 8) {
            DatePicker("", selection: $pickerDate, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                DatePicker("", selection: $pickerDate, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                Spacer()
                Stepper(value: $year, in: 2000...2100) {
                    Text(String(year)).font(.system(.body, design: .monospaced))
                }
                .onChange(of: year) { _, y in AppSettings.shared.year = y }
            }
            HStack {
                Spacer()
                Button("Use") {
                    date = pickerDate
                    year = Calendar.current.component(.year, from: pickerDate)
                    AppSettings.shared.year = year
                    raw = ""
                    showPicker = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            pickerDate = date ?? AppSettings.shared.nextScanDate()
            year = Calendar.current.component(.year, from: pickerDate)
        }
    }

    // MARK: - Parsing

    private var parsed: NumericDateStamp { NumericDateParser.parse(raw) }

    private var isValid: Bool { parsed.isValid }

    private var previewText: String {
        if raw.isEmpty {
            if let date { return DueFormat.format(date) }
            return "No due time"
        }
        guard parsed.isValid, parsed.hasDate else { return "Type MMDDHHMM…" }
        guard let built = resolved(rollForward: true)?.date else { return "Invalid date" }
        return DueFormat.format(built)
    }

    /// Resolves the typed stamp without touching state, so it is safe to call
    /// while the view is rendering.
    private func resolved(rollForward: Bool) -> (date: Date, year: Int)? {
        NumericDateParser.date(from: parsed, year: year, rollForward: rollForward)
    }

    private func liveCommit() {
        // Commit as soon as a date is recognizable, not only once the trailing
        // minutes are typed. The preview treats a missing time as midnight, so
        // the bound value must agree with what the field shows; otherwise a date
        // typed without minutes is silently dropped when the form is saved.
        guard parsed.hasDate, let result = resolved(rollForward: true) else { return }
        apply(result)
    }

    private func commit() {
        guard !raw.isEmpty, let result = resolved(rollForward: true) else { return }
        apply(result)
    }

    private func apply(_ result: (date: Date, year: Int)) {
        date = result.date
        if year != result.year {
            year = result.year
            AppSettings.shared.year = result.year
        }
    }

    private func clear() {
        date = nil
        raw = ""
        year = AppSettings.shared.year
    }

    private func prefill() {
        guard let date else { return }
        pickerDate = date
        year = Calendar.current.component(.year, from: date)
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        raw = String(format: "%02d%02d%02d%02d",
                     c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}

/// Shared due-date text formatting, usable without the generic view type.
public enum DueFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    public static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public static func format(_ date: Date) -> String {
        var text = dayFormatter.string(from: date)
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        if (c.hour ?? 0) != 0 || (c.minute ?? 0) != 0 {
            text += " · " + timeFormatter.string(from: date)
        }
        return text
    }
}
