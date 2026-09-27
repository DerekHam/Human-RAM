import Foundation

public enum WidgetShared {
    /// App Group shared with the widget. Replace `TEAMID` with your Apple
    /// Team ID and keep it in sync with `Resources/*.entitlements`.
    public static let appGroup = "TEAMID.com.example.humanram"

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(appGroup)", isDirectory: true)
    }

    public static var snapshotURL: URL {
        containerURL.appendingPathComponent("ram-tasks.json")
    }
}

public struct WidgetTask: Codable, Identifiable, Hashable {
    public let id: UUID
    public var text: String
    public var dueAt: Date?
    public var priority: Int
    public var pinned: Bool

    public init(id: UUID, text: String, dueAt: Date?, priority: Int, pinned: Bool) {
        self.id = id
        self.text = text
        self.dueAt = dueAt
        self.priority = priority
        self.pinned = pinned
    }
}

public struct WidgetSnapshot: Codable {
    public var updatedAt: Date
    public var tasks: [WidgetTask]

    public init(updatedAt: Date, tasks: [WidgetTask]) {
        self.updatedAt = updatedAt
        self.tasks = tasks
    }
}

public enum WidgetSnapshotStore {
    public static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: WidgetShared.snapshotURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        let directory = WidgetShared.containerURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: WidgetShared.snapshotURL, options: .atomic)
    }
}
