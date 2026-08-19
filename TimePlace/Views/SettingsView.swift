import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PreferencesSettingsView()
                        .environmentObject(auth)
                } label: {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    HouseholdsSettingsView()
                } label: {
                    Label("Households", systemImage: "house")
                }

                NavigationLink {
                    DevicesSettingsView()
                        .environmentObject(auth)
                } label: {
                    Label("Devices", systemImage: "display")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}