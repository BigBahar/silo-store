import AuthenticationServices
import SwiftUI
import SiloLyricsKit

@MainActor
final class NowPlayingModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    enum Status: Equatable {
        case notConfigured, signedOut, nothingPlaying, loadingLyrics, noLyrics, instrumental, ready
        case error(String)
    }

    @Published private(set) var status: Status = .signedOut
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var timeline: LyricsTimeline?
    @Published private(set) var plainLyrics: String?
    @Published private(set) var clock = PlaybackClock(progress: 0, sampledAt: .now, isPlaying: false)
    @Published private(set) var currentIndex: Int?

    /// Seconds; positive shows lyrics earlier. Persisted.
    @Published var userOffset: TimeInterval = UserDefaults.standard.double(forKey: "lyricsOffset") {
        didSet {
            UserDefaults.standard.set(userOffset, forKey: "lyricsOffset")
            clock.userOffset = userOffset
        }
    }

    private let auth: SpotifyAuth
    private let player = SpotifyPlayerClient()
    private let lrclib = LRCLIBClient()
    private let live = LiveActivityController()
    private var tokens: SpotifyTokens? = Keychain.load()
    private var loop: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var lastPoll = Date.distantPast
    private var pollInterval: TimeInterval = 3
    private var authSession: ASWebAuthenticationSession?

    override init() {
        let id = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        auth = SpotifyAuth(config: SpotifyAuthConfig(clientID: id))
        super.init()
        status = !auth.config.isConfigured ? .notConfigured : (tokens == nil ? .signedOut : .nothingPlaying)
    }

    // MARK: Lifecycle

    func start() {
        guard loop == nil, tokens != nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.step()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func signOut() {
        stop()
        Keychain.clear()
        tokens = nil
        nowPlaying = nil
        timeline = nil
        plainLyrics = nil
        currentIndex = nil
        status = auth.config.isConfigured ? .signedOut : .notConfigured
        Task { await live.end() }
    }

    // MARK: Sign-in

    func signIn() {
        guard auth.config.isConfigured else { status = .notConfigured; return }
        let pkce = PKCEPair.make()
        let state = UUID().uuidString
        let session = ASWebAuthenticationSession(
            url: auth.authorizeURL(pkce: pkce, state: state), callbackURLScheme: "silolyrics"
        ) { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                guard let url else {
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.status = .error("Spotify sign-in failed")
                    }
                    return
                }
                do {
                    let code = try self.auth.code(from: url, expectedState: state)
                    let t = try await self.auth.exchange(code: code, verifier: pkce.verifier)
                    Keychain.save(t)
                    self.tokens = t
                    self.status = .nothingPlaying
                    self.start()
                } catch {
                    self.status = .error("Spotify sign-in failed")
                }
            }
        }
        session.presentationContextProvider = self
        authSession = session
        session.start()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    // MARK: Loop

    private func step() async {
        if Date().timeIntervalSince(lastPoll) >= pollInterval { await poll() }
        if timeline != nil {
            let idx = timeline?.index(at: clock.position(at: .now))
            if idx != currentIndex {
                currentIndex = idx
                pushActivity()
            }
        }
    }

    private func poll() async {
        lastPoll = .now
        do {
            guard let token = try await validToken() else { return }
            do {
                apply(try await player.currentlyPlaying(accessToken: token.accessToken))
            } catch SpotifyPlayerError.unauthorized {
                tokens?.expiresAt = .distantPast
                apply(try await player.currentlyPlaying(accessToken: try await validToken()?.accessToken ?? ""))
            }
            pollInterval = 3
        } catch SpotifyPlayerError.rateLimited(let wait) {
            pollInterval = max(wait, 5)
        } catch SpotifyAuthError.http(let code) where code == 400 || code == 401 {
            signOut()
        } catch {
            // Transient network error: keep the last state and retry on the next poll.
        }
    }

    private func validToken() async throws -> SpotifyTokens? {
        guard var t = tokens else { return nil }
        if t.isExpired() {
            t = try await auth.refresh(t)
            tokens = t
            Keychain.save(t)
        }
        return t
    }

    private func apply(_ np: NowPlaying?) {
        guard let np else {
            if nowPlaying != nil { Task { await live.end() } }
            nowPlaying = nil
            timeline = nil
            plainLyrics = nil
            currentIndex = nil
            status = .nothingPlaying
            return
        }
        clock = PlaybackClock(progress: np.progress, sampledAt: .now, isPlaying: np.isPlaying, userOffset: userOffset)
        let changed = np.trackID != nowPlaying?.trackID
        nowPlaying = np
        if changed { loadLyrics(for: np) } else { pushActivity() }
    }

    private func loadLyrics(for np: NowPlaying) {
        lyricsTask?.cancel()
        timeline = nil
        plainLyrics = nil
        currentIndex = nil
        status = .loadingLyrics
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let result = try? await lrclib.lyrics(for: np.query)
            guard !Task.isCancelled, nowPlaying?.trackID == np.trackID else { return }
            timeline = result?.synced
            plainLyrics = result?.plain
            status = result == nil ? .noLyrics : result!.instrumental ? .instrumental : (result!.synced != nil ? .ready : .noLyrics)
            currentIndex = timeline?.index(at: clock.position(at: .now))
            await live.start(for: np)
            pushActivity()
        }
    }

    private func pushActivity() {
        guard let np = nowPlaying else { return }
        let lines = timeline?.lines ?? []
        let i = currentIndex
        let current = i.map { lines[$0].text } ?? ""
        let next = (i.map { $0 + 1 } ?? 0) < lines.count ? lines[(i.map { $0 + 1 } ?? 0)].text : ""
        let state = LyricsActivityAttributes.ContentState(
            line: current.isEmpty ? "♪" : current, nextLine: next, isPlaying: np.isPlaying && clock.isPlaying)
        Task { await live.update(state) }
    }
}
