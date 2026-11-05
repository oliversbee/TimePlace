import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    
    // Listen to the theme globally
    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    var body: some View {
        Group {
            if auth.isInitializing {
                Color.black
                    .ignoresSafeArea()
            } else if auth.isAuthenticated {
                CaptureHomeView()
            } else {
                LoginView()
            }
        }
        // Apply the preferred color scheme to everything
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
    }
}