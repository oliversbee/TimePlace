import SwiftUI

struct PreferencesSettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var viewModel = SettingsViewModel()

    let intervalOptions = [60, 300, 600, 1800, 3600]

    var body: some View {
        Form {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }

            Section("Display Settings") {
                TextField("Display Name", text: $viewModel.displayName)
                    .onSubmit {
                        saveChanges()
                    }

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
        }
        .navigationTitle("Preferences")
        .task {
            if let userId = auth.userId {
                await viewModel.loadData(currentUserId: userId)
            }
        }
    }

    private func saveChanges() {
        if let userId = auth.userId {
            Task {
                await viewModel.savePreferences(currentUserId: userId)
            }
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