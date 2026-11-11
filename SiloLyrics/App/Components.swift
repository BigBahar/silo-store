import SwiftUI

/// Design tokens for Silo Lyrics (dark first; Silo teal accent).
enum Theme {
    static let accent = Color(red: 0.133, green: 0.725, blue: 0.8)      // #22B9CC
    static let surface = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.14)
}

/// Pill button used instead of the system bordered button styles.
struct PillButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .font(.callout)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(prominent ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: prominent ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Offset nudge: two round buttons around a value, replacing the system Stepper.
struct OffsetControl: View {
    @Binding var value: TimeInterval

    var body: some View {
        HStack(spacing: 14) {
            round("minus", label: "Show lyrics later") { value = max(-5, value - 0.25) }
            Text(String(format: "%+.2fs", value))
                .font(.callout.monospacedDigit())
                .frame(minWidth: 64)
                .accessibilityLabel("Lyrics offset \(String(format: "%.2f", value)) seconds")
            round("plus", label: "Show lyrics earlier") { value = min(5, value + 0.25) }
        }
    }

    private func round(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout.weight(.bold))
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}
