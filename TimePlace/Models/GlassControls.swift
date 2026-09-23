import SwiftUI

// =============================================================================
// APP ACCENT
// =============================================================================
//
// One bold color, spent in exactly one place per screen (the primary action).
// Everything else in the camera UI stays neutral glass so the accent reads as
// a choice, not wallpaper.
//
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
//
// The circular chrome buttons (settings, flash, camera-flip). Real blur
// material rather than a flat black plate, forced to a dark appearance so it
// reads the same over bright sky or a dark room — the same reasoning the
// system Camera app uses for its own overlay controls.
//
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
// CAPTURE MODE TOGGLE
// =============================================================================
//
// Replaces the plain segmented Picker with a capsule that matches the icon
// buttons around it. The selected segment slides rather than cross-fades —
// one small, deliberate motion, not decoration sprinkled everywhere.
//
struct CaptureModeToggle: View {

    @Binding var mode: CaptureMode
    @Namespace private var namespace

    var body: some View {

        HStack(spacing: 2) {

            ForEach(CaptureMode.allCases) { option in

                Text(option.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(mode == option ? .black : .white)
                    .frame(width: 46, height: 30)
                    .background {

                        if mode == option {

                            Capsule()
                                .fill(.white)
                                .matchedGeometryEffect(
                                    id: "modeSelection",
                                    in: namespace
                                )
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {

                        guard mode != option else {
                            return
                        }

                        withAnimation(
                            .spring(response: 0.28, dampingFraction: 0.88)
                        ) {
                            mode = option
                        }
                    }
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

// =============================================================================
// STATUS BANNER
// =============================================================================
//
// Same glass language for the inline error message, so it reads as part of
// the app rather than a leftover debug label.
//
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

// =============================================================================
// CAPSULE BUTTON STYLES
// =============================================================================
//
// Secondary: neutral glass, for actions like "Retake" that undo forward
// progress.
// Primary: the one place the app accent is spent, for the forward action.
//
struct SecondaryCapsuleButtonStyle: ButtonStyle {

    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {

        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(minWidth: 130)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .opacity(isDisabled ? 0.5 : (configuration.isPressed ? 0.75 : 1))
            .environment(\.colorScheme, .dark)
    }
}

struct PrimaryCapsuleButtonStyle: ButtonStyle {

    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {

        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(minWidth: 130)
            .background(Color.appAccent, in: Capsule())
            .opacity(isDisabled ? 0.5 : (configuration.isPressed ? 0.85 : 1))
            .shadow(
                color: Color.appAccent.opacity(isDisabled ? 0 : 0.35),
                radius: 12,
                y: 5
            )
    }
}
