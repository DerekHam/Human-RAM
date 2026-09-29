import Foundation
import Combine

public struct ReleaseInfo: Equatable {
    public let version: String
    public let name: String
    public let url: URL
    public let notes: String

    public init(version: String, name: String, url: URL, notes: String) {
        self.version = version
        self.name = name
        self.url = url
        self.notes = notes
    }
}

/// Checks GitHub Releases for a newer version. Privacy first: one anonymous GET
/// to the public releases API, no parameters, no telemetry. Disable in Settings.
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public static let releasesAPI = URL(string: "https://api.github.com/repos/DerekHam/Human-RAM/releases?per_page=20")!
    public static let releasesPage = URL(string: "https://github.com/DerekHam/Human-RAM/releases/latest")!

    @Published public private(set) var available: ReleaseInfo?
    @Published public private(set) var isChecking = false
    @Published public private(set) var lastError: String?

    private let session: URLSession
    private let currentVersion: String

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Checks only when the user has opted in (Settings → Updates).
    public func checkIfEnabled() {
        guard AppSettings.shared.checkForUpdates else { return }
        check()
    }

    /// Fetches releases and publishes `available` when a newer stable one exists.
    public func check() {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("HumanRAM", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            let result = Self.evaluate(data: data, error: error, currentVersion: self.currentVersion)
            DispatchQueue.main.async {
                self.isChecking = false
                switch result {
                case .success(let info):
                    self.available = info
                case .failure(let message):
                    self.lastError = message
                }
            }
        }.resume()
    }

    enum Evaluation {
        case success(ReleaseInfo?)
        case failure(String)
    }

    static func evaluate(data: Data?, error: Error?, currentVersion: String) -> Evaluation {
        if let error { return .failure(error.localizedDescription) }
        guard let data else { return .failure("No response from GitHub.") }
        struct Payload: Decodable {
            let tag_name: String
            let name: String?
            let html_url: String
            let body: String?
            let draft: Bool
            let prerelease: Bool
        }
        let releases: [Payload]
        do {
            releases = try JSONDecoder().decode([Payload].self, from: data)
        } catch {
            return .failure("Could not read the release list.")
        }
        let current = versionNumbers(currentVersion)
        var best: (ReleaseInfo, [Int])?
        for release in releases where !release.draft && !release.prerelease {
            guard let url = URL(string: release.html_url) else { continue }
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            let numbers = versionNumbers(version)
            guard isNewer(numbers, than: current) else { continue }
            let info = ReleaseInfo(version: version,
                                   name: release.name ?? release.tag_name,
                                   url: url,
                                   notes: release.body ?? "")
            if let existing = best, !isNewer(numbers, than: existing.1) { continue }
            best = (info, numbers)
        }
        return .success(best?.0)
    }

    static func versionNumbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    static func isNewer(_ candidate: [Int], than current: [Int]) -> Bool {
        let count = max(candidate.count, current.count)
        for i in 0..<count {
            let a = i < candidate.count ? candidate[i] : 0
            let b = i < current.count ? current[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
