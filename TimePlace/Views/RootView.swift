import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.isInitializing {
                Color(UIColor.systemBackground).ignoresSafeArea()
            } else if auth.isAuthenticated {
                CaptureHomeView()
                    .onAppear {
                        NotificationManager.shared.requestAuthorization()
                    }
            } else {
                LoginView()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active && auth.isAuthenticated {
                NotificationManager.shared.scheduleUpcomingPrompts()
            }
        }
    }
}