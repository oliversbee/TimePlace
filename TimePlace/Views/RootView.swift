import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase // NEW: Listen to app lifecycle
    
    // Listen to the theme globally
    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    var body: some View {
        Group {
            if auth.isInitializing {
                Color.black
                    .ignoresSafeArea()
            } else if auth.isAuthenticated {
                CaptureHomeView()
                    .onAppear {
                        // Request notification permission once they are logged in and reach the camera
                        NotificationManager.shared.requestAuthorization()
                    }
            } else {
                LoginView()
            }
        }
        // Apply the preferred color scheme to everything
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
        .onChange(of: scenePhase) { newPhase in
            // When the app comes back to the foreground, top up the 7-day schedule
            if newPhase == .active && auth.isAuthenticated {
                NotificationManager.shared.scheduleUpcomingPrompts()
            }
        }
    }
}