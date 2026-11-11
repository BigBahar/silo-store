import SwiftUI
import SiloLyricsKit

struct RootView: View {
    @EnvironmentObject private var model: NowPlayingModel
    @EnvironmentObject private var updates: UpdateChecker
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Backdrop(url: model.nowPlaying?.artworkURL)
            VStack(spacing: 0) {
                header
                content
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model).environmentObject(updates)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nowPlaying?.title ?? "Silo Lyrics")
                    .font(.headline).lineLimit(1)
                if let artist = model.nowPlaying?.artist {
                    Text(artist).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button { showSettings = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                    if updates.available != nil {
                        Circle().fill(Theme.accent).frame(width: 10, height: 10)
                    }
                }
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(updates.available == nil ? "Settings" : "Settings, update available")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .notConfigured:
            message("Spotify isn't set up", detail: "Add your Spotify client ID to Config.xcconfig and rebuild.")
        case .signedOut:
            message("Connect Spotify", detail: "Silo Lyrics reads what you're playing and shows synced lyrics in the Dynamic Island.") {
                PillButton(title: "Connect Spotify", systemImage: "link", prominent: true) { model.signIn() }
            }
        case .nothingPlaying:
            message("Nothing playing", detail: "Start a song in Spotify and the lyrics follow along.")
        case .loadingLyrics:
            message("Finding lyrics…", detail: nil)
        case .noLyrics:
            if let plain = model.plainLyrics, !plain.isEmpty {
                ScrollView { Text(plain).font(.title3.weight(.medium)).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                message("No lyrics found", detail: "LRCLIB has nothing for this track yet.")
            }
        case .instrumental:
            message("Instrumental", detail: nil)
        case .ready:
            if let timeline = model.timeline { LyricsScroller(timeline: timeline, index: model.currentIndex) }
        case .error(let text):
            message(text, detail: nil) { PillButton(title: "Try again", systemImage: "arrow.clockwise") { model.signIn() } }
        }
    }

    private func message(_ title: String, detail: String?) -> some View {
        message(title, detail: detail) { EmptyView() }
    }

    private func message(_ title: String, detail: String?, @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            }
            action()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

struct LyricsScroller: View {
    let timeline: LyricsTimeline
    let index: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 80)
                    ForEach(Array(timeline.lines.enumerated()), id: \.offset) { i, line in
                        let isCurrent = i == index
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.35))
                            .scaleEffect(isCurrent ? 1 : 0.92, anchor: .leading)
                            .blur(radius: isCurrent ? 0 : 1.2)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isCurrent)
                            .id(i)
                    }
                    Color.clear.frame(height: 240)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: index) { _, new in
                guard let new else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) { proxy.scrollTo(new, anchor: UnitPoint(x: 0.5, y: 0.3)) }
            }
        }
    }
}

struct Backdrop: View {
    let url: URL?

    var body: some View {
        ZStack {
            Color.black
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill().blur(radius: 70).opacity(0.55)
                } else {
                    LinearGradient(colors: [Theme.accent.opacity(0.35), .black], startPoint: .top, endPoint: .bottom)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
