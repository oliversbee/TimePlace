import SwiftUI

struct HouseholdMembersView: View {

    let household: Household

    @ObservedObject var manager: HouseholdManager

    @State private var members: [HouseholdMember] = []
    @State private var nicknames: [UUID: String] = [:]
    @State private var hiddenUsers: Set<UUID> = []

    @State private var isLoadingMembers = false
    @State private var showingLeaveConfirmation = false

    // MARK: - Filtered Household Members (Excludes Current User)

    var otherMembers: [HouseholdMember] {
        guard let currentUserId = manager.currentUserId else {
            return []
        }

        return members.filter { member in
            member.userId != currentUserId
        }
    }

    var body: some View {

        Form {

            // MARK: Household

            Section {

                HStack {

                    Text("Join Code")

                    Spacer()

                    Text(household.joinCode)
                        .font(
                            .system(
                                .body,
                                design: .monospaced
                            )
                        )
                        .foregroundColor(.gray)
                }
            }

            // MARK: Members

            Section("Members") {

                if isLoadingMembers {

                    HStack {
                        Spacer()

                        ProgressView()

                        Spacer()
                    }

                } else if otherMembers.isEmpty {

                    Text("No members to display.")
                        .foregroundColor(.gray)

                } else {

                    ForEach(otherMembers) { member in

                        HStack {
                            // Inline Name TextField
                            TextField(
                                "Name",
                                text: Binding(
                                    get: {
                                        displayName(for: member)
                                    },
                                    set: { newName in
                                        nicknames[member.userId] = newName
                                    }
                                ),
                                onCommit: {
                                    let currentName = nicknames[member.userId] ?? ""
                                    Task {
                                        let success = await manager.setNickname(
                                            targetUserId: member.userId,
                                            nickname: currentName
                                        )
                                        if !success {
                                            // Revert or reload on failure
                                            await loadMembers()
                                        }
                                    }
                                }
                            )
                            .foregroundColor(.primary)

                            Spacer()

                            // Toggle: ON = Visible, OFF = Hidden
                            Toggle(
                                "Visible",
                                isOn: Binding(
                                    get: {
                                        !hiddenUsers.contains(member.userId)
                                    },
                                    set: { isVisible in
                                        Task {
                                            if isVisible {
                                                await unhide(member)
                                            } else {
                                                await hide(member)
                                            }
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                        }
                    }
                }
            }

            // MARK: Leave

            Section {

                Button(
                    "Leave Household",
                    role: .destructive
                ) {
                    showingLeaveConfirmation = true
                }
            }
        }

        .navigationTitle(household.name)
        .navigationBarTitleDisplayMode(.inline)

        // MARK: Load

        .task {
            await loadMembers()
        }

        // MARK: Leave Confirmation

        .alert(
            "Leave Household?",
            isPresented: $showingLeaveConfirmation
        ) {

            Button(
                "Leave",
                role: .destructive
            ) {

                Task {
                    await leaveHousehold()
                }
            }

            Button(
                "Cancel",
                role: .cancel
            ) {}

        } message: {

            Text(
                "You will be removed from \(household.name)."
            )
        }
    }

    // MARK: - Display Name

    private func displayName(
        for member: HouseholdMember
    ) -> String {

        if let nickname = nicknames[member.userId],
           !nickname.isEmpty {
            return nickname
        }

        return member.name ?? "Unnamed User"
    }

    // MARK: - Load Members

    private func loadMembers() async {

        isLoadingMembers = true

        let loadedMembers =
            await manager.fetchHouseholdMembers(
                householdId: household.id
            )

        let loadedNicknames =
            await manager.fetchNicknames()

        let loadedHiddenUsers =
            await manager.fetchHiddenUsers()

        members = loadedMembers
        nicknames = loadedNicknames
        hiddenUsers = loadedHiddenUsers

        isLoadingMembers = false
    }

    // MARK: - Hide

    private func hide(
        _ member: HouseholdMember
    ) async {

        let success =
            await manager.hideUser(
                targetUserId: member.userId
            )

        if success {
            hiddenUsers.insert(
                member.userId
            )
        }
    }

    // MARK: - Unhide

    private func unhide(
        _ member: HouseholdMember
    ) async {

        let success =
            await manager.unhideUser(
                targetUserId: member.userId
            )

        if success {
            hiddenUsers.remove(
                member.userId
            )
        }
    }

    // MARK: - Leave

    private func leaveHousehold() async {

        _ = await manager.leaveHousehold(
            householdId: household.id
        )
    }
}