import BackgroundTasks
import SwiftUI

/// Finds new Silo Lyrics builds in the Silo Store source and hands the install to Silo Store / SideStore.
/// iOS does not let an app replace itself, so "install" opens the store's install URL (one tap, no website).
@MainActor
final class UpdateChecker: ObservableObject {
    struct Available: Equatable {
        let version: String
        let downloadURL: URL
        let notes: String
    }

    static let taskID = "com.bigbahar.silolyrics.updatecheck"
    private static let sourceURL = URL(string: "https://bigbahar.github.io/silo-store/source.json")!
    private static let bundleID = "com.bigbahar.silolyrics"

    @Published private(set) var available: Available?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func check() async {
        checking = true
        defer { checking = false }
        available = try? await Self.fetchLatest(newerThan: currentVersion)
        lastChecked = .now
    }

    func install() {
        guard let a = available else { return }
        var c = URLComponents(string: "sidestore://install")!
        c.queryItems = [.init(name: "url", value: a.downloadURL.absoluteString)]
        if let url = c.url { UIApplication.shared.open(url) }
    }

    nonisolated static func fetchLatest(newerThan current: String) async throws -> Available? {
        let (data, _) = try await URLSession.shared.data(from: sourceURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = root["apps"] as? [[String: Any]],
              let app = apps.first(where: { $0["bundleIdentifier"] as? String == bundleID }) else { return nil }
        // Newest stable release from releaseChannels, else the legacy top-level fields.
        var release: [String: Any]?
        if let channels = app["releaseChannels"] as? [[String: Any]],
           let track = channels.first(where: { $0["track"] as? String == "stable" }) ?? channels.first,
           let releases = track["releases"] as? [[String: Any]] {
            release = releases.first
        }
        let top = release ?? app
        guard let version = top["version"] as? String,
              let urlString = top["downloadURL"] as? String, let url = URL(string: urlString),
              version.compare(current, options: .numeric) == .orderedDescending else { return nil }
        return Available(version: version, downloadURL: url,
                         notes: (top["localizedDescription"] ?? top["versionDescription"]) as? String ?? "")
    }

    // MARK: Background checks

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            schedule()
            let work = Task {
                let found = try? await fetchLatest(
                    newerThan: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
                UserDefaults.standard.set(found?.version, forKey: "pendingUpdateVersion")
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
}
