import SwiftUI

@main
struct SiloLyricsApp: App {
    @StateObject private var model = NowPlayingModel()
    @StateObject private var updates = UpdateChecker()
    @Environment(\.scenePhase) private var phase

    init() {
        UpdateChecker.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(updates)
                .preferredColorScheme(.dark)
                .task {
                    model.start()
                    await updates.check()
                }
        }
        .onChange(of: phase) { _, new in
            switch new {
            case .active:
                model.start()
                Task { await updates.check() }
            case .background:
                UpdateChecker.schedule()
            default:
                break
            }
        }
    }
}
