import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme // NEW
    
    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    // NEW: Computed property to fix the "Auto" mode bug
    private var resolvedColorScheme: ColorScheme {
        let mode = AppearanceMode(rawValue: appearanceRaw) ?? .system
        switch mode {
        case .system: return systemColorScheme
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var body: some View {
        Group {
            if auth.isInitializing {
                Color.black
                    .ignoresSafeArea()
            } else if auth.isAuthenticated {
                CaptureHomeView()
                    .onAppear {
                        NotificationManager.shared.requestAuthorization()
                    }
            } else {
                LoginView()
            }
        }
        // CHANGED: Use the resolved scheme instead of the raw enum
        .preferredColorScheme(resolvedColorScheme)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active && auth.isAuthenticated {
                NotificationManager.shared.scheduleUpcomingPrompts()
            }
        }
    }
}