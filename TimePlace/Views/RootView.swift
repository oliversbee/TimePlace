import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var actualSystemColorScheme // Reads TRUE device setting
    
    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var resolvedColorScheme: ColorScheme {
        let mode = AppearanceMode(rawValue: appearanceRaw) ?? .system
        switch mode {
        case .system: return actualSystemColorScheme
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var body: some View {
        Group {
            if auth.isInitializing {
                Color.black.ignoresSafeArea()
            } else if auth.isAuthenticated {
                CaptureHomeView()
                    .onAppear {
                        NotificationManager.shared.requestAuthorization()
                    }
            } else {
                LoginView()
            }
        }
        // Pass the true system setting down to all children
        .environment(\.systemColorScheme, actualSystemColorScheme) 
        .preferredColorScheme(resolvedColorScheme)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active && auth.isAuthenticated {
                NotificationManager.shared.scheduleUpcomingPrompts()
            }
        }
    }
}