import SwiftUI

public struct DueChip: View {
    public let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
            Text(label)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }

    private var label: String {
        let cal = Calendar.current
        if date < Date() { return "overdue · " + DueFormat.format(date) }
        if cal.isDateInToday(date) {
            return "today " + DueFormat.time(date)
        }
        if cal.isDateInTomorrow(date) {
            return "tomorrow " + DueFormat.time(date)
        }
        return DueFormat.format(date)
    }

    private var color: Color {
        if date < Date() { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .secondary
    }
}

public struct StartChip: View {
    public let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.circle")
            Text("starts " + DueFormat.format(date))
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.purple.opacity(0.18), in: Capsule())
        .foregroundStyle(.purple)
    }
}
