import SwiftUI

/// The menu revealed when tapping the top-left burger menu button.
struct SideMenuView: View {
    var onOpenSettings: () -> Void
    var onSignOut: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Menu Background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(.all)

            VStack(alignment: .leading, spacing: 12) {
                // Menu Header
                Text("Menu")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 8)

                // Settings Button
                Button {
                    onOpenSettings()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 24)

                        Text("Settings")
                            .font(.body)
                            .foregroundColor(.primary)

                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer()

                // Sign Out Button
                Button(role: .destructive) {
                    onSignOut()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.body)

                        Text("Sign Out")
                            .font(.body)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea(.all)
        .preferredColorScheme(.dark)
    }
}