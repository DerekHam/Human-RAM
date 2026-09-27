import SwiftUI

/// The journal: captured thoughts, filed with timestamps.
public struct JournalView: View {
    @EnvironmentObject private var store: ItemStore
    @State private var query = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Journal").font(.title2).fontWeight(.semibold)
                    Text("\(store.journaledNotes.count) thoughts kept")
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
                Text("Nothing here yet. Review your notes at night and they'll be filed here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(headline(for: group.day)).font(.headline)
                                    Text("\(group.items.count)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                                ForEach(group.items) { item in
                                    entry(item)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private func entry(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain")
                .foregroundStyle(.blue)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label(item.createdAt.formatted(date: .omitted, time: .shortened), systemImage: "pencil")
                    if let filed = item.completedAt {
                        Label("filed " + filed.formatted(date: .omitted, time: .shortened), systemImage: "book.closed")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                store.unjournalNote(id: item.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Move back to the notes inbox")
            Button {
                store.delete(id: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private struct DayGroup {
        let day: Date
        let items: [Item]
    }

    private var groups: [DayGroup] {
        let filtered = store.journaledNotes.filter {
            query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)
        }
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { item in
            cal.startOfDay(for: item.createdAt)
        }
        return dict
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    private func headline(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
}