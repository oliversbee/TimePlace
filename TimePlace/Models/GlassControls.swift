import SwiftUI

// =============================================================================
// APP ACCENT
// =============================================================================
extension Color {
    static let appAccent = Color(
        red: 1.0,
        green: 0.42,
        blue: 0.29
    )
}

// =============================================================================
// GLASS ICON BUTTON
// =============================================================================
struct GlassIconButton: View {

    let systemName: String
    var tint: Color = .white
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {

        Button(action: action) {

            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(GlassPressStyle())
        .environment(\.colorScheme, .dark)
    }
}

private struct GlassPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {

        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// =============================================================================
// STATUS BANNER
// =============================================================================
struct GlassStatusBanner: View {

    let text: String

    var body: some View {

        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .environment(\.colorScheme, .dark)
    }
}