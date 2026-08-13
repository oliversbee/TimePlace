import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            if auth.isAuthenticated {
                CaptureHomeView()
            } else {
                LoginView()
            }
        }
    }
}
