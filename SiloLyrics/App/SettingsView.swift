import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: NowPlayingModel
    @EnvironmentObject private var updates: UpdateChecker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Settings").font(.title2.bold())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44).background(Theme.surface, in: Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Close")
                }

                section("Lyrics timing") {
                    Text("Nudge if the lyrics feel early or late.").font(.footnote).foregroundStyle(.white.opacity(0.6))
                    OffsetControl(value: $model.userOffset)
                }

                section("Spotify") {
                    PillButton(title: "Disconnect Spotify", systemImage: "person.crop.circle.badge.xmark") {
                        model.signOut()
                        dismiss()
                    }
                }

                section("Version \(updates.currentVersion)") {
                    if let a = updates.available {
                        Text("Version \(a.version) is ready.").font(.callout)
                        if !a.notes.isEmpty { Text(a.notes).font(.footnote).foregroundStyle(.white.opacity(0.6)) }
                        PillButton(title: "Update now", systemImage: "arrow.down.circle", prominent: true) { updates.install() }
                    } else {
                        Text(updates.checking ? "Checking for updates…" : "You're up to date.")
                            .font(.callout).foregroundStyle(.white.opacity(0.7))
                        PillButton(title: "Check again", systemImage: "arrow.clockwise") { Task { await updates.check() } }
                    }
                }
                Spacer()
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
            body()
        }
    }
}
