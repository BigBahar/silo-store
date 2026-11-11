import XCTest
@testable import SiloLyricsKit

final class LRCParserTests: XCTestCase {
    func testBasicLinesAndMetadata() {
        let lrc = """
        [ar: Someone]
        [ti: Song]
        [00:12.00] First
        [00:17.5]Second
        [01:02.345] Third
        """
        XCTAssertEqual(LRCParser.parse(lrc), [
            LyricLine(time: 12, text: "First"),
            LyricLine(time: 17.5, text: "Second"),
            LyricLine(time: 62.345, text: "Third"),
        ])
    }

    func testMultipleTimestampsSortedAndEmptyLinesKept() {
        let lrc = "[00:30.00][00:10.00]Chorus\n[00:20.00]\n"
        XCTAssertEqual(LRCParser.parse(lrc), [
            LyricLine(time: 10, text: "Chorus"),
            LyricLine(time: 20, text: ""),
            LyricLine(time: 30, text: "Chorus"),
        ])
    }

    func testOffsetAndWordTags() {
        let lrc = "[offset:+500]\n[00:10.00]<00:10.00>Hel<00:10.40>lo"
        XCTAssertEqual(LRCParser.parse(lrc), [LyricLine(time: 9.5, text: "Hello")])
    }

    func testGarbageIsIgnored() {
        XCTAssertEqual(LRCParser.parse("no tags here\n[xx:yy]nope\n[00:61.00]bad"), [])
    }
}

final class SyncEngineTests: XCTestCase {
    let timeline = LyricsTimeline(lines: [
        LyricLine(time: 5, text: "a"), LyricLine(time: 10, text: "b"), LyricLine(time: 20, text: "c"),
    ])

    func testIndexLookup() {
        XCTAssertNil(timeline.index(at: 0))
        XCTAssertNil(timeline.index(at: 4.99))
        XCTAssertEqual(timeline.index(at: 5), 0)
        XCTAssertEqual(timeline.index(at: 19.9), 1)
        XCTAssertEqual(timeline.index(at: 999), 2)
    }

    func testClockInterpolatesOnlyWhilePlaying() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let playing = PlaybackClock(progress: 10, sampledAt: t0, isPlaying: true, userOffset: 0.5)
        XCTAssertEqual(playing.position(at: t0.addingTimeInterval(2)), 12.5, accuracy: 0.001)
        let paused = PlaybackClock(progress: 10, sampledAt: t0, isPlaying: false)
        XCTAssertEqual(paused.position(at: t0.addingTimeInterval(30)), 10, accuracy: 0.001)
    }
}

final class LRCLIBTests: XCTestCase {
    func testDecodeAndResult() throws {
        let json = #"{"duration":200,"instrumental":false,"plainLyrics":"x","syncedLyrics":"[00:01.00] hi"}"#
        let r = LRCLIBClient.result(from: try LRCLIBClient.decode(Data(json.utf8)))
        XCTAssertEqual(r.synced?.lines, [LyricLine(time: 1, text: "hi")])
        XCTAssertEqual(r.plain, "x")
    }

    func testBestMatchPrefersClosestSyncedWithinThreeSeconds() throws {
        func rec(_ d: Double, _ synced: String?) throws -> LRCLIBClient.Record {
            let s = synced.map { "\"\($0)\"" } ?? "null"
            return try LRCLIBClient.decode(Data(#"{"duration":\#(d),"plainLyrics":"p","syncedLyrics":\#(s)}"#.utf8))
        }
        let records = [try rec(190, "[00:01.00]far"), try rec(201, "[00:01.00]near"), try rec(200, nil)]
        XCTAssertEqual(LRCLIBClient.bestMatch(in: records, duration: 200)?.syncedLyrics, "[00:01.00]near")
        XCTAssertNil(LRCLIBClient.bestMatch(in: [try rec(100, "[00:01.00]x")], duration: 200))
    }
}

final class SpotifyTests: XCTestCase {
    func testPKCEMatchesRFC7636Vector() {
        XCTAssertEqual(PKCEPair.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let p = PKCEPair.make()
        XCTAssertEqual(p.verifier.count, 96)
        XCTAssertEqual(p.challenge, PKCEPair.challenge(for: p.verifier))
    }

    func testAuthorizeURLAndCallback() throws {
        let auth = SpotifyAuth(config: SpotifyAuthConfig(clientID: "abc"))
        let url = auth.authorizeURL(pkce: PKCEPair(verifier: "v", challenge: "c"), state: "s1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(items.first { $0.name == "scope" }?.value,
                       "user-read-currently-playing user-read-playback-state")

        let ok = URL(string: "silolyrics://callback?code=XYZ&state=s1")!
        XCTAssertEqual(try auth.code(from: ok, expectedState: "s1"), "XYZ")
        XCTAssertThrowsError(try auth.code(from: ok, expectedState: "other"))
        XCTAssertThrowsError(try auth.code(from: URL(string: "silolyrics://callback?error=access_denied&state=s1")!,
                                           expectedState: "s1"))
    }

    func testCurrentlyPlayingParsing() throws {
        let json = """
        {"is_playing":true,"progress_ms":12500,"currently_playing_type":"track",
         "item":{"id":"t1","name":"Song","duration_ms":200000,
                 "artists":[{"name":"A"},{"name":"B"}],
                 "album":{"name":"Alb","images":[{"url":"https://i/s.jpg","width":64},{"url":"https://i/l.jpg","width":640}]}}}
        """
        let np = try XCTUnwrap(SpotifyPlayerClient.parse(Data(json.utf8)))
        XCTAssertEqual(np.artist, "A, B")
        XCTAssertEqual(np.progress, 12.5, accuracy: 0.001)
        XCTAssertEqual(np.artworkURL?.absoluteString, "https://i/l.jpg")
        XCTAssertNil(try SpotifyPlayerClient.parse(Data(#"{"is_playing":true,"currently_playing_type":"ad"}"#.utf8)))
    }

    func testTokenExpiry() {
        let t = SpotifyTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(t.isExpired(at: Date(timeIntervalSince1970: 950)))
        XCTAssertFalse(t.isExpired(at: Date(timeIntervalSince1970: 900)))
    }
}
