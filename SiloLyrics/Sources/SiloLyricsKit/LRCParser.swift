import Foundation

public struct LyricLine: Equatable, Sendable {
    public let time: TimeInterval
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

/// Parses synced lyrics in LRC format: `[mm:ss.xx] text`, several timestamps per line,
/// `[offset:±ms]`, and enhanced word tags `<mm:ss.xx>` (stripped, line timing only).
public enum LRCParser {
    public static func parse(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        var offset: TimeInterval = 0

        for rawLine in raw.split(whereSeparator: \.isNewline) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var stamps: [TimeInterval] = []

            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = parseTimestamp(tag) {
                    stamps.append(t)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                } else if stamps.isEmpty {
                    // Metadata tag (ar, ti, al, by, …) on its own line.
                    rest = ""
                    break
                } else {
                    break
                }
                rest = rest[rest.index(after: close)...]
            }

            guard !stamps.isEmpty else { continue }
            let text = stripWordTags(String(rest)).trimmingCharacters(in: .whitespaces)
            for t in stamps {
                // A positive LRC offset makes lyrics appear sooner.
                lines.append(LyricLine(time: max(0, t - offset), text: text))
            }
        }

        return lines.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }

    /// `mm:ss`, `mm:ss.x`, `mm:ss.xx`, `mm:ss.xxx` (also `mm:ss:xx`).
    static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Double(parts[0]), minutes >= 0 else { return nil }
        var seconds = parts[1]
        var fraction = ""
        if parts.count == 3 {
            fraction = String(parts[2])
        } else if let dot = seconds.firstIndex(of: ".") {
            fraction = String(seconds[seconds.index(after: dot)...])
            seconds = seconds[..<dot]
        }
        guard let s = Double(seconds), s >= 0, s < 60 else { return nil }
        var f = 0.0
        if !fraction.isEmpty {
            guard fraction.allSatisfy(\.isNumber), let digits = Double(fraction) else { return nil }
            f = digits / pow(10, Double(fraction.count))
        }
        return minutes * 60 + s + f
    }

    private static func stripWordTags(_ s: String) -> String {
        guard s.contains("<") else { return s }
        var out = ""
        var inTag = false
        for ch in s {
            if ch == "<" { inTag = true } else if ch == ">" && inTag { inTag = false } else if !inTag { out.append(ch) }
        }
        return out
    }
}
