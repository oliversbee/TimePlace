import SwiftUI

// Enum to manage the Picker options cleanly
enum DisplayIntervalOption: Hashable {
    case min1, min10, min30, hour1, custom
}

struct DisplayConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthManager
    
    // Uses the shared EnvironmentObject so data is consistent
    @EnvironmentObject var viewModel: SettingsViewModel

    let device: PairedDevice
    
    @State private var selectedInterval: DisplayIntervalOption = .min1
    @State private var customHours = 0
    @State private var customMinutes = 1

    var body: some View {
        NavigationStack {
            Form {
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }

                // MARK: - Display Interval Time
                Section(header: Text("Display Interval Time")) {
                    Picker("Interval", selection: $selectedInterval) {
                        Text("1 min").tag(DisplayIntervalOption.min1)
                        Text("10 min").tag(DisplayIntervalOption.min10)
                        Text("30 min").tag(DisplayIntervalOption.min30)
                        Text("1 hour").tag(DisplayIntervalOption.hour1)
                        Text("Custom").tag(DisplayIntervalOption.custom)
                    }
                    .onChange(of: selectedInterval) { newValue in
                        if let seconds = standardSeconds(for: newValue) {
                            viewModel.imageIntervalSeconds = seconds
                            savePreferences()
                        } else {
                            updateCustomInterval()
                        }
                    }
                    
                    // Scroll Wheels for Custom Time
                    if selectedInterval == .custom {
                        HStack(spacing: 0) {
                            Picker("Hours", selection: $customHours) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            
                            Picker("Minutes", selection: $customMinutes) {
                                ForEach(0..<60, id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        }
                        .onChange(of: customHours) { _ in updateCustomInterval() }
                        .onChange(of: customMinutes) { _ in updateCustomInterval() }
                    }
                }

                // MARK: - Visible Members on Screen
                Section(header: Text("Visible Members on Screen")) {
                    if viewModel.familyMembers.isEmpty {
                        Text("No household members found.").foregroundColor(.gray)
                    } else {
                        ForEach(viewModel.familyMembers) { member in
                            // Uses the assigned nickname, falls back to name
                            let displayName = viewModel.nicknames[member.id] ?? member.name
                            
                            Toggle(
                                "Show \(displayName)'s Photos",
                                isOn: Binding(
                                    get: { !viewModel.hiddenUserIds.contains(member.id) },
                                    set: { _ in
                                        if let userId = auth.userId {
                                            Task {
                                                await viewModel.toggleHideUser(currentUserId: userId, familyUserId: member.id)
                                            }
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
            }
            .navigationTitle(device.name.isEmpty ? "Configure Display" : device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let userId = auth.userId {
                    await viewModel.loadData(currentUserId: userId)
                    viewModel.displayName = device.name
                    initializeIntervalSelection()
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func standardSeconds(for option: DisplayIntervalOption) -> Int? {
        switch option {
        case .min1: return 60
        case .min10: return 600
        case .min30: return 1800
        case .hour1: return 3600
        case .custom: return nil
        }
    }
    
    private func initializeIntervalSelection() {
        let seconds = viewModel.imageIntervalSeconds
        if seconds == 60 { selectedInterval = .min1 }
        else if seconds == 600 { selectedInterval = .min10 }
        else if seconds == 1800 { selectedInterval = .min30 }
        else if seconds == 3600 { selectedInterval = .hour1 }
        else {
            selectedInterval = .custom
            customHours = seconds / 3600
            customMinutes = (seconds % 3600) / 60
        }
    }
    
    private func updateCustomInterval() {
        let totalSeconds = (customHours * 3600) + (customMinutes * 60)
        // Ensure it's at least 1 minute to prevent 0 second intervals
        viewModel.imageIntervalSeconds = max(totalSeconds, 60)
        savePreferences()
    }
    
    private func savePreferences() {
        if let userId = auth.userId {
            Task {
                await viewModel.savePreferences(currentUserId: userId)
            }
        }
    }
}