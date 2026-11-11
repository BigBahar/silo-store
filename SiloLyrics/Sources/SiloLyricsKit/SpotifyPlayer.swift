import Foundation

public struct NowPlaying: Equatable, Sendable {
    public let trackID: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let progress: TimeInterval
    public let isPlaying: Bool
    public let artworkURL: URL?

    public var query: TrackQuery {
        TrackQuery(title: title, artist: artist, album: album, duration: duration)
    }
}

public enum SpotifyPlayerError: Error, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
}

public struct SpotifyPlayerClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// nil when nothing is playing (204), or an ad / podcast episode.
    public func currentlyPlaying(accessToken: String) async throws -> NowPlaying? {
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 204: return nil
        case 200: return try Self.parse(data)
        case 401: throw SpotifyPlayerError.unauthorized
        case 429:
            let wait = Double((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5
            throw SpotifyPlayerError.rateLimited(retryAfter: wait)
        default: throw SpotifyPlayerError.http(status)
        }
    }

    static func parse(_ data: Data) throws -> NowPlaying? {
        struct Image: Decodable { let url: String; let width: Int? }
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String; let images: [Image] }
        struct Item: Decodable {
            let id: String?
            let name: String
            let duration_ms: Double
            let artists: [Artist]
            let album: Album?
        }
        struct Body: Decodable {
            let is_playing: Bool
            let progress_ms: Double?
            let currently_playing_type: String?
            let item: Item?
        }
        let b = try JSONDecoder().decode(Body.self, from: data)
        guard b.currently_playing_type == "track", let item = b.item, let id = item.id else { return nil }
        let art = item.album?.images.max { ($0.width ?? 0) < ($1.width ?? 0) }.flatMap { URL(string: $0.url) }
        return NowPlaying(
            trackID: id, title: item.name,
            artist: item.artists.map(\.name).joined(separator: ", "),
            album: item.album?.name ?? "",
            duration: item.duration_ms / 1000,
            progress: (b.progress_ms ?? 0) / 1000,
            isPlaying: b.is_playing, artworkURL: art
        )
    }
}
