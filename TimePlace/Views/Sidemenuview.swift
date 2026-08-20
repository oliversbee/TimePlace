import SwiftUI

/// The menu revealed when tapping the top-left burger menu button.
struct SideMenuView: View {
    var onOpenSettings: () -> Void
    var onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()

            Button {
                onOpenSettings()
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 10)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 24)

            Spacer()

            Button(role: .destructive) {
                onSignOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            Color.white
                .ignoresSafeArea() // Flushes the white background to the physical screen edges
        )
    }
}