import SwiftUI

/// The menu revealed when tapping the top-left burger menu button.
struct SideMenuView: View {
    var onOpenSettings: () -> Void
    var onSignOut: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Liquid Glass Translucent Background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(.all)

            VStack(alignment: .leading, spacing: 8) {
                // Menu Header Section
                Text("Menu")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 12)

                // Settings Item
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
                    .padding(.vertical, 12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer()

                // Sign Out Action Button
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
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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