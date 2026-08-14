import SwiftUI

/// The menu revealed behind the camera when the user drags it to the right.
/// For now this is just a Sign Out button — more menu items can be added
/// above it later.
struct SideMenuView: View {
    var onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // TODO: real menu items go here (settings, profile, etc.)

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
            .tint(.white)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.black)
    }
}
