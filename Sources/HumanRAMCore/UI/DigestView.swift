import SwiftUI

/// The daily scan: everything that needs your attention, in one place.
public struct DigestView: View {
    @EnvironmentObject private var store: ItemStore
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Overdue", items: overdue, accent: .red, empty: "Nothing overdue. Good.")
                    section("Today", items: today, accent: .orange, empty: "Nothing due today.")
                    section("Upcoming", items: upcoming, accent: .blue, empty: "Nothing scheduled ahead.")
                    section("In RAM", items: store.loaded, accent: .green, empty: "RAM is empty.")
                    backlogSection
                }
                .padding(18)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Scan").font(.title2).fontWeight(.semibold)
                Text(Date().formatted(date: .complete, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.applyDecay()
                store.applyTimeWindow()
            } label: {
                Label("Load today's set", systemImage: "arrow.down.circle")
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private func section(_ title: String, items: [Item], accent: Color, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(title.uppercased()).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(items) { item in
                    DigestRow(item: item)
                }
            }
        }
    }

    private var backlogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive").font(.caption2)
                Text("HARD DRIVE").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Text("\(store.backlog.count)").font(.caption).foregroundStyle(.secondary)
            }
            if store.backlog.isEmpty {
                Text("Nothing stored away.").font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(store.backlog) { item in
                    DigestRow(item: item)
                }
            }
        }
    }

    // MARK: - Buckets

    private var overdue: [Item] {
        let start = Calendar.current.startOfDay(for: Date())
        return store.items
            .filter { !$0.deleted && $0.state != .done && ($0.dueAt ?? .distantFuture) < start }
            .sorted(by: ItemStore.ramOrder)
    }

    private var today: [Item] {
        let cal = Calendar.current
        return store.items
            .filter { !$0.deleted && $0.state != .done && $0.dueAt != nil && cal.isDateInToday($0.dueAt!) }
            .sorted(by: ItemStore.ramOrder)
    }

    private var upcoming: [Item] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let end = cal.date(byAdding: .day, value: 8, to: cal.startOfDay(for: Date())) ?? Date()
        return store.items
            .filter { !$0.deleted && $0.state != .done && $0.dueAt != nil && $0.dueAt! >= start && $0.dueAt! < end }
            .sorted(by: ItemStore.ramOrder)
    }
}

struct DigestRow: View {
    @EnvironmentObject private var store: ItemStore
    let item: Item

    var body: some View {
        HStack(spacing: 8) {
            Button { store.complete(id: item.id) } label: {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                if let start = item.startAt, item.hasUpcomingStart {
                    StartChip(date: start)
                }
                if let due = item.dueAt { DueChip(date: due) }
            }
            Spacer()
            Button {
                AppRouter.shared.presentEditItem(item.id)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            if item.state == .backlog {
                Button("Load") { store.loadToRAM(id: item.id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            } else {
                Button {
                    store.spillToDisk(id: item.id)
                } label: {
                    Image(systemName: "externaldrive.badge.minus")
                }
                .buttonStyle(.borderless)
                .help("Spill to hard drive")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Mark done") { store.complete(id: item.id) }
            Button("Edit…") { AppRouter.shared.presentEditItem(item.id) }
            Divider()
            if item.state == .backlog {
                Button("Load into RAM") { store.loadToRAM(id: item.id) }
            } else {
                Button("Spill to hard drive") { store.spillToDisk(id: item.id) }
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
}