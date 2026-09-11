import SwiftUI

struct HouseholdsSettingsView: View {

    @EnvironmentObject var householdManager: HouseholdManager

    @State private var newHouseholdName = ""
    @State private var joinCode = ""
    @State private var showCreateSection = false
    @State private var showJoinSection = false

    var body: some View {

        Form {

            if let error = householdManager.errorMessage {

                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }


            // MARK: - Joined Households

            Section("Joined Households") {

                if householdManager.households.isEmpty && !householdManager.isLoading {

                    Text("No households joined yet.")
                        .foregroundColor(.gray)

                } else {

                    ForEach(householdManager.households) { h in

                        NavigationLink {
                            HouseholdMembersView(
                                household: h,
                                manager: householdManager
                            )
                        } label: {

                            HStack {

                                Text(h.name)
                                    .fontWeight(.semibold)

                                Spacer()

                                Text(h.joinCode)
                                    .font(
                                        .system(
                                            .body,
                                            design: .monospaced
                                        )
                                    )
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }


            // MARK: - Actions

            Section("Actions") {

                Button("Join a Household") {
                    showJoinSection.toggle()
                }

                Button("Create New Household") {
                    showCreateSection.toggle()
                }
            }


            // MARK: - Join Household

            if showJoinSection {

                Section("Enter Join Code") {

                    TextField(
                        "6-character code",
                        text: $joinCode
                    )
                    .textInputAutocapitalization(
                        .characters
                    )

                    Button("Submit Code") {

                        Task {

                            if await householdManager.joinHousehold(
                                code: joinCode
                            ) {

                                joinCode = ""
                                showJoinSection = false
                            }
                        }
                    }
                    .disabled(
                        joinCode.count < 6 ||
                        householdManager.isLoading
                    )
                }
            }


            // MARK: - Create Household

            if showCreateSection {

                Section("Create Household") {

                    TextField(
                        "Household Name",
                        text: $newHouseholdName
                    )

                    Button("Create") {

                        Task {

                            if await householdManager.createHousehold(
                                name: newHouseholdName
                            ) {

                                newHouseholdName = ""
                                showCreateSection = false
                            }
                        }
                    }
                    .disabled(
                        newHouseholdName.isEmpty ||
                        householdManager.isLoading
                    )
                }
            }
        }
        .navigationTitle("Households")
    }
}