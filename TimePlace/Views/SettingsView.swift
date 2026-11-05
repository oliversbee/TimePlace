import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var householdManager: HouseholdManager
    @Environment(\.dismiss) private var dismiss

    // Needed so the light/dark toggle from the Profile page updates this screen live.
    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    @StateObject private var settingsViewModel = SettingsViewModel()

    // Sheet for Frame pairing
    @State private var showAddFrameSheet = false

    // Alerts for Household logic
    @State private var showJoinHouseholdAlert = false
    @State private var joinCode = ""

    @State private var showCreateHouseholdAlert = false
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
                                        .frame(width: 28)
                                    Text("View All Households")
                                }
                            }
                        }
                    }

                    // Join Household Button
                    Button {
                        showJoinHouseholdAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 28)
                            Text("Join Household")
                        }
                        .foregroundColor(.blue)
                    }

                    // Create Household Button
                    Button {
                        showCreateHouseholdAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 28)
                            Text("Create Household")
                        }
                        .foregroundColor(.blue)
                    }
                } header: {
                    Text("HOUSEHOLD")
                }

                // MARK: - Frame Section
                if !householdManager.pairedDevices.isEmpty {
                    Section {
                        ForEach(householdManager.pairedDevices) { device in
                            // Goes straight to DisplayConfigView
                            NavigationLink {
                                DisplayConfigView(device: device)
                                    .environmentObject(auth)
                                    .environmentObject(settingsViewModel)
                            } label: {
                                HStack {
                                    SettingsIcon(systemName: "checkmark", color: .orange)
                                    Text(device.name.isEmpty ? "My Frame" : device.name)
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text("FRAME")
                    }
                } else {
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

                // MARK: - Account / Profile (NEW)
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        PreferencesSettingsView()
                            .environmentObject(auth)
                            .environmentObject(settingsViewModel)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20, weight: .regular))
                    }
                    .accessibilityLabel("Account")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    Button(role: .destructive) {
                        Task {
                            await auth.signOut()
                        }
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding()
                    .background(Color(UIColor.systemGroupedBackground))
                }
            }
        }
        // Replaces the previous hard-coded `.preferredColorScheme(.light)`
        // so the Profile → Appearance toggle works here.
        .preferredColorScheme(
            (AppearanceMode(rawValue: appearanceRaw) ?? .system).colorScheme
        )
        .sheet(isPresented: $showAddFrameSheet) {
            AddFrameView()
                .environmentObject(householdManager)
        }
        .alert("Join Household", isPresented: $showJoinHouseholdAlert) {
            TextField("6-character code", text: $joinCode)
                .textInputAutocapitalization(.characters)

            Button("Cancel", role: .cancel) {
                joinCode = ""
            }
            Button("Join") {
                Task {
                    if await householdManager.joinHousehold(code: joinCode) {
                        joinCode = ""
                    }
                }
            }
            .disabled(joinCode.count < 6)
        } message: {
            Text("Enter the 6-character join code for the household.")
        }
        .alert("Create Household", isPresented: $showCreateHouseholdAlert) {
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
            guard let userId = auth.userId else { return }
            await settingsViewModel.loadData(currentUserId: userId)
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

    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

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
        // Follows the same Appearance setting instead of being locked to light.
        .preferredColorScheme(
            (AppearanceMode(rawValue: appearanceRaw) ?? .system).colorScheme
        )
    }
}