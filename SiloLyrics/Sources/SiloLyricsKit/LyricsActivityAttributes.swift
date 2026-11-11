#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Shared by the app (starts/updates) and the widget extension (renders).
public struct LyricsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var line: String
        public var nextLine: String
        public var isPlaying: Bool

        public init(line: String, nextLine: String, isPlaying: Bool) {
            self.line = line
            self.nextLine = nextLine
            self.isPlaying = isPlaying
        }
    }

    public var title: String
    public var artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }
}
#endif
