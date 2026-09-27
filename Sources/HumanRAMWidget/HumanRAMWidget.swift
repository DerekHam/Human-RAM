import SwiftUI
import WidgetKit
import HumanRAMShared

struct RAMEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
}

struct RAMProvider: TimelineProvider {
    func placeholder(in context: Context) -> RAMEntry {
        RAMEntry(date: Date(), tasks: [
            WidgetTask(id: UUID(), text: "Write the thing down", dueAt: Date().addingTimeInterval(3600), priority: 3, pinned: true),
            WidgetTask(id: UUID(), text: "Review tonight's notes", dueAt: nil, priority: 2, pinned: false),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (RAMEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RAMEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> RAMEntry {
        RAMEntry(date: Date(), tasks: WidgetSnapshotStore.load()?.tasks ?? [])
    }
}

struct RAMWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RAMEntry

    private var limit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 9
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.tasks.isEmpty {
                empty
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.tasks.prefix(limit)) { task in
                        row(task)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "memorychip")
            Text("Human RAM").font(.caption).fontWeight(.semibold)
            Spacer()
            Text("\(entry.tasks.count)")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .foregroundStyle(.secondary)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("RAM is empty").font(.callout).foregroundStyle(.secondary)
            Text("Capture a task to load it here.").font(.caption2).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private func row(_ task: WidgetTask) -> some View {
        HStack(spacing: 6) {
            if task.pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
            } else if task.priority == 3 {
                Image(systemName: "exclamationmark.2").font(.caption2).foregroundStyle(.red)
            } else {
                Image(systemName: "circle").font(.caption2).foregroundStyle(.tertiary)
            }
            Text(task.text)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = task.dueAt {
                Text(DueLabel.text(due))
                    .font(.caption2)
                    .foregroundStyle(DueLabel.color(due))
                    .lineLimit(1)
            }
        }
    }
}

enum DueLabel {
    static func text(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInTomorrow(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return "tmrw " + f.string(from: date)
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    static func color(_ date: Date) -> Color {
        if date < Date() { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .secondary
    }
}

struct RAMWidget: Widget {
    let kind = "HumanRAMWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RAMProvider()) { entry in
            RAMWidgetView(entry: entry)
        }
        .configurationDisplayName("Human RAM")
        .description("The tasks currently loaded in your RAM.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct HumanRAMWidgetBundle: WidgetBundle {
    var body: some Widget {
        RAMWidget()
    }
}
