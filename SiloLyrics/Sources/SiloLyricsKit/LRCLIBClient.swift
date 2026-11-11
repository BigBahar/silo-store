import Foundation

public struct LyricsResult: Equatable, Sendable {
    public let synced: LyricsTimeline?
    public let plain: String?
    public let instrumental: Bool
}

public struct TrackQuery: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval

    public init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

/// Client for https://lrclib.net (free, no key). Exact match first, then a search fallback.
public struct LRCLIBClient: Sendable {
    struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private let session: URLSession
    private let base = URL(string: "https://lrclib.net/api")!
    private let userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "SiloLyrics/1.0 (https://github.com/BigBahar/silo-store)") {
        self.session = session
        self.userAgent = userAgent
    }

    public func lyrics(for q: TrackQuery) async throws -> LyricsResult? {
        if let exact = try await get(path: "get", items: [
            ("track_name", q.title), ("artist_name", q.artist),
            ("album_name", q.album), ("duration", String(Int(q.duration.rounded()))),
        ]) {
            return Self.result(from: exact)
        }
        let found: [Record]? = try await get(path: "search", items: [
            ("track_name", q.title), ("artist_name", q.artist),
        ])
        guard let best = Self.bestMatch(in: found ?? [], duration: q.duration) else { return nil }
        return Self.result(from: best)
    }

    static func decode(_ data: Data) throws -> Record { try JSONDecoder().decode(Record.self, from: data) }

    static func result(from r: Record) -> LyricsResult {
        let lines = r.syncedLyrics.map(LRCParser.parse) ?? []
        return LyricsResult(
            synced: lines.isEmpty ? nil : LyricsTimeline(lines: lines),
            plain: r.plainLyrics,
            instrumental: r.instrumental ?? false
        )
    }

    /// Prefer synced results whose duration is within 3 s of the track, closest first.
    static func bestMatch(in records: [Record], duration: TimeInterval) -> Record? {
        records
            .filter { $0.syncedLyrics?.isEmpty == false && abs(($0.duration ?? .infinity) - duration) <= 3 }
            .min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
            ?? records.first { $0.plainLyrics?.isEmpty == false && abs(($0.duration ?? .infinity) - duration) <= 3 }
    }

    private func get<T: Decodable>(path: String, items: [(String, String)]) async throws -> T? {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        var req = URLRequest(url: comps.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
