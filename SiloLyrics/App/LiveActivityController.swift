import ActivityKit
import SiloLyricsKit

/// Owns the single Live Activity (Dynamic Island + Lock Screen). Updates here run locally,
/// so they only continue while the app process is alive; see docs/silo-lyrics/re-notes.md.
@MainActor
final class LiveActivityController {
    private var activity: Activity<LyricsActivityAttributes>?
    private var trackID: String?

    func start(for np: NowPlaying) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if trackID == np.trackID, activity != nil { return }
        await end()
        let attrs = LyricsActivityAttributes(title: np.title, artist: np.artist)
        let state = LyricsActivityAttributes.ContentState(line: "♪", nextLine: "", isPlaying: np.isPlaying)
        activity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
        trackID = np.trackID
    }

    func update(_ state: LyricsActivityAttributes.ContentState) async {
        await activity?.update(.init(state: state, staleDate: nil))
    }

    func end() async {
        for a in Activity<LyricsActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        trackID = nil
    }
}
