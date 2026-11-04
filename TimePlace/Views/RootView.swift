import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            if auth.isInitializing {
                // Show a black screen while checking the session
                Color.black
                    .ignoresSafeArea()
            } else if auth.isAuthenticated {
                CaptureHomeView()
            } else {
                LoginView()
            }
        }
    }
}