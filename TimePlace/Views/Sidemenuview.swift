import SwiftUI

/// The white side menu revealed when the camera is dragged to the right.
struct SideMenuView: View {
    var onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Future menu items can go here.

            Spacer()

            Button {
                // Do NOT close the menu here.
                // Signing out changes the authentication state, which causes
                // the app's root view to return to the login screen.
                onSignOut()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")

                    Text("Sign Out")
                        .fontWeight(.semibold)

                    Spacer()
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            // Plain prevents SwiftUI's bordered button style from producing
            // the unwanted white/filled bar seen at the bottom.
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}
