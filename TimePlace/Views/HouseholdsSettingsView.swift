import SwiftUI

struct HouseholdsSettingsView: View {
    @StateObject private var manager = HouseholdManager()

    @State private var newHouseholdName = ""
    @State private var joinCode = ""
    @State private var showCreateSection = false
    @State private var showJoinSection = false

    var body: some View {
        Form {
            if let error = manager.errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }

            Section("Joined Households") {
                if manager.households.isEmpty && !manager.isLoading {
                    Text("No households joined yet.").foregroundColor(.gray)
                } else {
                    ForEach(manager.households) { h in
                        HStack {
                            Text(h.name).fontWeight(.semibold)
                            Spacer()
                            Text(h.joinCode)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            Section("Actions") {
                Button("Join a Household") { showJoinSection.toggle() }
                Button("Create New Household") { showCreateSection.toggle() }
            }

            if showJoinSection {
                Section("Enter Join Code") {
                    TextField("6-character code", text: $joinCode)
                        .autocapitalize(.allCharacters)
                    Button("Submit Code") {
                        Task {
                            if await manager.joinHousehold(code: joinCode) {
                                joinCode = ""
                                showJoinSection = false
                            }
                        }
                    }
                    .disabled(joinCode.count < 6 || manager.isLoading)
                }
            }

            if showCreateSection {
                Section("Create Household") {
                    TextField("Household Name", text: $newHouseholdName)
                    Button("Create") {
                        Task {
                            if await manager.createHousehold(name: newHouseholdName) {
                                newHouseholdName = ""
                                showCreateSection = false
                            }
                        }
                    }
                    .disabled(newHouseholdName.isEmpty || manager.isLoading)
                }
            }
        }
        .navigationTitle("Households")
        .task {
            await manager.fetchHouseholds()
        }
    }
}