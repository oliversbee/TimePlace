import SwiftUI

/// The menu revealed behind the camera when the user drags it to the right.
/// The menu remains fully interactive while it is open.
struct SideMenuView: View {
    var onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // TODO: real menu items go here (settings, profile, etc.)

            Spacer()

            Button {
                onSignOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")

                    Text("Sign Out")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.black)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white)
    }
}
