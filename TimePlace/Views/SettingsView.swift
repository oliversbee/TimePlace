import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Settings

                Section {
                    NavigationLink {
                        PreferencesSettingsView()
                            .environmentObject(auth)
                    } label: {
                        Label(
                            "Preferences",
                            systemImage: "slider.horizontal.3"
                        )
                    }

                    NavigationLink {
                        HouseholdsSettingsView()
                            .environmentObject(auth)
                    } label: {
                        Label(
                            "Households",
                            systemImage: "house"
                        )
                    }

                    NavigationLink {
                        DevicesSettingsView()
                            .environmentObject(auth)
                    } label: {
                        Label(
                            "Devices",
                            systemImage: "display"
                        )
                    }
                }

                // MARK: - Account

                Section {
                    Button(role: .destructive) {
                        Task {
                            await auth.signOut()
                        }
                    } label: {
                        HStack {
                            Label(
                                "Sign Out",
                                systemImage: "rectangle.portrait.and.arrow.right"
                            )

                            Spacer()
                        }
                    }
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