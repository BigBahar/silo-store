import Foundation

/// Sorted synced lines with a lookup for "which line is current at time t".
public struct LyricsTimeline: Equatable, Sendable {
    public let lines: [LyricLine]

    public init(lines: [LyricLine]) {
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }

    /// Index of the last line whose time is <= `t`, or nil before the first line.
    public func index(at t: TimeInterval) -> Int? {
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : lo - 1
    }
}

/// Turns Spotify's sparse `progress_ms` samples into a continuous playback position.
public struct PlaybackClock: Equatable, Sendable {
    public var progress: TimeInterval
    public var sampledAt: Date
    public var isPlaying: Bool
    /// User nudge in seconds; positive shows lyrics earlier.
    public var userOffset: TimeInterval

    public init(progress: TimeInterval, sampledAt: Date, isPlaying: Bool, userOffset: TimeInterval = 0) {
        self.progress = progress
        self.sampledAt = sampledAt
        self.isPlaying = isPlaying
        self.userOffset = userOffset
    }

    public func position(at now: Date) -> TimeInterval {
        let elapsed = isPlaying ? max(0, now.timeIntervalSince(sampledAt)) : 0
        return max(0, progress + elapsed + userOffset)
    }
}
