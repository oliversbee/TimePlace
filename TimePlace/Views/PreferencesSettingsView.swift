import SwiftUI

struct PreferencesSettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var viewModel: SettingsViewModel

    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    let intervalOptions = [60, 300, 600, 1800, 3600]

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }

            Section("Display Settings") {
                TextField("Display Name", text: $viewModel.displayName)
                    .onSubmit { saveChanges() }

                Toggle(
                    "Show My Own Photos",
                    isOn: Binding(
                        get: { viewModel.showOwnImage },
                        set: { newValue in
                            viewModel.showOwnImage = newValue
                            saveChanges()
                        }
                    )
                )

                Picker(
                    "Image Swap Interval",
                    selection: Binding(
                        get: { viewModel.imageIntervalSeconds },
                        set: { newValue in
                            viewModel.imageIntervalSeconds = newValue
                            saveChanges()
                        }
                    )
                ) {
                    ForEach(intervalOptions, id: \.self) { seconds in
                        Text(intervalString(for: seconds)).tag(seconds)
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    if isDeleting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Deleting…")
                        }
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(isDeleting)
            } footer: {
                Text("Your photos, household memberships, and paired frames will be permanently removed after a 30‑day grace period. You'll be signed out immediately.")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(appearanceBinding.wrappedValue.colorScheme)
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await auth.deleteAccount()
                    isDeleting = false
                }
            }
        } message: {
            Text("This is permanent. Your account will be scheduled for deletion and you'll be signed out now.")
        }
    }

    private func saveChanges() {
        if let userId = auth.userId {
            Task { await viewModel.savePreferences(currentUserId: userId) }
        }
    }

    private func intervalString(for seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min\(minutes == 1 ? "" : "s")"
        } else {
            let hours = minutes / 60
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
    }
}