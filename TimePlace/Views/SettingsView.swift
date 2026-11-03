import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var householdManager = HouseholdManager()
    
    @State private var showAddFrameSheet = false
    @State private var showAddHouseholdAlert = false
    @State private var newHouseholdName = ""

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Household Section
                Section {
                    if householdManager.households.isEmpty && !householdManager.isLoading {
                        Text("No households joined yet.")
                            .foregroundColor(.secondary)
                    } else {
                        // Show up to 3 households
                        ForEach(householdManager.households.prefix(3)) { h in
                            NavigationLink {
                                HouseholdMembersView(
                                    household: h,
                                    manager: householdManager
                                )
                            } label: {
                                HStack {
                                    SettingsIcon(systemName: "house.fill", color: .green)
                                    Text(h.name)
                                }
                            }
                        }
                        
                        // View All Option (only if > 3)
                        if householdManager.households.count > 3 {
                            NavigationLink {
                                HouseholdsSettingsView()
                                    .environmentObject(auth)
                                    .environmentObject(householdManager)
                            } label: {
                                HStack {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 28) // Aligns with icons
                                    Text("View All Households")
                                }
                            }
                        }
                        
                        // Add Household Button
                        Button {
                            showAddHouseholdAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 28) // Aligns with icons
                                Text("Add Household")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                } header: {
                    Text("HOUSEHOLD")
                }

                // MARK: - Frame Section
                if !householdManager.pairedDevices.isEmpty {
                    Section {
                        ForEach(householdManager.pairedDevices) { device in
                            NavigationLink {
                                DevicesSettingsView()
                                    .environmentObject(auth)
                                    .environmentObject(householdManager)
                                    .environmentObject(settingsViewModel)
                            } label: {
                                HStack {
                                    SettingsIcon(systemName: "checkmark", color: .orange)
                                    Text(device.name.isEmpty ? "My Frame" : device.name)
                                    Spacer()
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
        .preferredColorScheme(.light) 
        .sheet(isPresented: $showAddFrameSheet) {
            AddFrameView()
                .environmentObject(householdManager)
        }
        .alert("Add Household", isPresented: $showAddHouseholdAlert) {
            TextField("Household Name", text: $newHouseholdName)
            Button("Cancel", role: .cancel) {
                newHouseholdName = ""
            }
            Button("Create") {
                Task {
                    if await householdManager.createHousehold(name: newHouseholdName) {
                        newHouseholdName = ""
                    }
                }
            }
            .disabled(newHouseholdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for your new household.")
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