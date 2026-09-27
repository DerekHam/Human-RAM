import SwiftUI

/// A look back at everything you've completed — the app's diary.
public struct DiaryView: View {
    @EnvironmentObject private var store: ItemStore
    @State private var query = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diary").font(.title2).fontWeight(.semibold)
                    Text("\(store.completed.count) things done")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(18)
            Divider()

            if groups.isEmpty {
                Spacer()
                Text("Nothing here yet. Complete something and it will appear.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(headline(for: group.day))
                                        .font(.headline)
                                    Text("\(group.items.count)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                                ForEach(group.items) { item in
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text(item.text)
                                        Spacer()
                                        if let c = item.completedAt {
                                            Text(c.formatted(date: .omitted, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Button {
                                            store.uncomplete(id: item.id)
                                        } label: {
                                            Image(systemName: "arrow.uturn.backward")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Move back to hard drive")
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private struct DayGroup {
        let day: Date
        let items: [Item]
    }

    private var groups: [DayGroup] {
        let filtered = store.completed.filter {
            query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)
        }
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { item -> Date in
            cal.startOfDay(for: item.completedAt ?? item.touchedAt)
        }
        return dict
            .map { DayGroup(day: $0.key, items: $0.value.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) }
            .sorted { $0.day > $1.day }
    }

    private func headline(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
}