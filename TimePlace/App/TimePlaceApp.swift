import SwiftUI

@main
struct TimePlaceApp: App {
    @StateObject private var auth = AuthManager()

    init() {
        // Ask for notification permission and schedule the next few
        // random daily prompts as soon as the app launches.
        NotificationManager.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .preferredColorScheme(.dark)
        }
    }
}
