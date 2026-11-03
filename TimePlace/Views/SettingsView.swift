import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var householdManager = HouseholdManager()
    
    @State private var showAddFrameSheet = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Household Section
                Section {
                    // Household Row
                    NavigationLink {
                        HouseholdsSettingsView()
                            .environmentObject(auth)
                            .environmentObject(householdManager)
                    } label: {
                        HStack {
                            SettingsIcon(systemName: "house.fill", color: .green)
                            Text("Elm Street House")
                            Spacer()
                            Text("4")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Members Row
                    NavigationLink {
                        // Placeholder for Members view if you add one later
                        HouseholdsSettingsView()
                            .environmentObject(auth)
                            .environmentObject(householdManager)
                    } label: {
                        HStack {
                            SettingsIcon(systemName: "person.2.fill", color: .purple)
                            Text("Members")
                        }
                    }
                    
                    // Add Household Button
                    Button {
                        // Action to add household
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 28) // Aligns with icons
                            Text("Add Household")
                        }
                        .foregroundColor(.blue)
                    }
                } header: {
                    Text("HOUSEHOLD")
                }

                // MARK: - Frame Section (Only if device is claimed)
                if !householdManager.pairedDevices.isEmpty {
                    Section {
                        if let device = householdManager.pairedDevices.first {
                            NavigationLink {
                                DevicesSettingsView()
                                    .environmentObject(auth)
                                    .environmentObject(householdManager)
                                    .environmentObject(settingsViewModel)
                            } label: {
                                HStack {
                                    SettingsIcon(systemName: "checkmark", color: .orange)
                                    Text(device.name.isEmpty ? "Living Room" : device.name)
                                    Spacer()
                                    Text("Selected")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Button {
                            showAddFrameSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 28)
                                Text("Add Frame")
                            }
                            .foregroundColor(.blue)
                        }
                    } header: {
                        Text("FRAME")
                    }
                } else {
                    // If no device is claimed, show Add Frame just above Sign Out
                    Section {
                        Button {
                            showAddFrameSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 28)
                                Text("Add Frame")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                
                // MARK: - Sign Out Section
                Section {
                    Button(role: .destructive) {
                        Task {
                            await auth.signOut()
                        }
                    } label: {
                        Text("Sign Out")
                            .fontWeight(.regular)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.light) // Forces the light mode look from your mockup
        .sheet(isPresented: $showAddFrameSheet) {
            AddFrameView()
                .environmentObject(householdManager)
        }
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

// =========================================================================
// HELPER: SETTINGS ICON STYLE
// =========================================================================
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// =========================================================================
// ADD FRAME VIEW (Pairing Logic)
// =========================================================================
struct AddFrameView: View {
    @EnvironmentObject var manager: HouseholdManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var deviceClaimCode = ""

    var body: some View {
        NavigationStack {
            Form {
                if let error = manager.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }
                
                Section(
                    header: Text("Pair New Frame"),
                    footer: Text("Enter the 6-character code displayed on your frame.")
                ) {
                    TextField(
                        "6-character display code",
                        text: $deviceClaimCode
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                    Button("Link Device") {
                        Task {
                            if await manager.pairDevice(claimCode: deviceClaimCode) {
                                deviceClaimCode = ""
                                await manager.fetchPairedDevices()
                                dismiss()
                            }
                        }
                    }
                    .disabled(deviceClaimCode.isEmpty || manager.isLoading)
                }
            }
            .navigationTitle("Add Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}