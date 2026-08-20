import SwiftUI

/// The menu revealed when tapping the top-left burger menu button.
struct SideMenuView: View {
    var onOpenSettings: () -> Void
    var onSignOut: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Liquid Glass Translucent Menu Background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(.all)

            VStack(alignment: .leading, spacing: 12) {
                // Menu Header Section
                Text("Menu")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 8)

                // Liquid Glass Settings Button
                Button {
                    onOpenSettings()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                            .font(.body.weight(.medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        Text("Settings")
                            .font(.body.weight(.medium))
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        colorScheme == .dark ? .white.opacity(0.2) : .white.opacity(0.6),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer()

                // Liquid Glass Sign Out Button
                Button(role: .destructive) {
                    onSignOut()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.body.weight(.semibold))

                        Text("Sign Out")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.red.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        colorScheme == .dark ? Color.red.opacity(0.3) : Color.red.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.red.opacity(0.08), radius: 8, x: 0, y: 4)
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea(.all)
    }
}