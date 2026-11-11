import ActivityKit
import SwiftUI
import WidgetKit
import SiloLyricsKit

@main
struct SiloLyricsWidgets: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}

struct LyricsLiveActivity: Widget {
    private let accent = Color(red: 0.133, green: 0.725, blue: 0.8)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            // Lock Screen / banner
            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.line)
                    .font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                if !context.state.nextLine.isEmpty {
                    Text(context.state.nextLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("\(context.attributes.title) · \(context.attributes.artist)")
                    .font(.caption).foregroundStyle(accent).lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .foregroundStyle(accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.state.line)
                            .font(.headline.weight(.bold)).multilineTextAlignment(.center)
                            .lineLimit(2).minimumScaleFactor(0.8)
                        if !context.state.nextLine.isEmpty {
                            Text(context.state.nextLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(accent)
            } compactTrailing: {
                Text(context.state.line)
                    .font(.caption2.weight(.semibold)).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}
