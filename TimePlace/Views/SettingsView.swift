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
                // MARK: - Default Options
                Section {
                    NavigationLink {
                        HouseholdsSettingsView()
                            .environmentObject(auth)
                            .environmentObject(householdManager)
                    } label: {
                        Label("Households", systemImage: "house")
                    }
                }

                // MARK: - Frame Option (Only if claimed)
                if !householdManager.pairedDevices.isEmpty {
                    Section {
                        NavigationLink {
                            DevicesSettingsView()
                                .environmentObject(auth)
                                .environmentObject(householdManager)
                                .environmentObject(settingsViewModel)
                        } label: {
                            Label("Frame", systemImage: "display")
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
            // MARK: - Bottom Actions (Add Frame & Sign Out)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    
                    // Native-looking list container for bottom buttons
                    VStack(spacing: 0) {
                        // Show "Add Frame" only if no devices are claimed
                        if householdManager.pairedDevices.isEmpty {
                            Button {
                                showAddFrameSheet = true
                            } label: {
                                HStack {
                                    Label("Add Frame", systemImage: "plus.circle")
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .padding(.leading, 16)
                        }
                        
                        // Sign Out Button
                        Button(role: .destructive) {
                            Task {
                                await auth.signOut()
                            }
                        } label: {
                            HStack {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .preferredColorScheme(.dark)
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
        .preferredColorScheme(.dark)
    }
}