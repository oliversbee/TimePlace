import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var householdManager = HouseholdManager()

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Settings

                Section {
                    NavigationLink {
                        PreferencesSettingsView()
                            .environmentObject(auth)
                            .environmentObject(settingsViewModel)
                    } label: {
                        Label(
                            "Preferences",
                            systemImage: "slider.horizontal.3"
                        )
                    }

                    NavigationLink {
                        HouseholdsSettingsView()
                            .environmentObject(auth)
                            .environmentObject(householdManager)
                    } label: {
                        Label(
                            "Households",
                            systemImage: "house"
                        )
                    }

                    NavigationLink {
                        DevicesSettingsView()
                            .environmentObject(auth)
                            .environmentObject(householdManager)
                            .environmentObject(settingsViewModel)
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
        .task {
            await preloadSettings()
        }
    }

    private func preloadSettings() async {
        guard let userId = auth.userId else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await settingsViewModel.loadData(currentUserId: userId)
            }

            group.addTask {
                await householdManager.fetchHouseholds()
            }

            group.addTask {
                await householdManager.fetchPairedDevices()
            }
        }
    }
}