import SwiftUI

struct HouseholdMembersView: View {

    let household: Household

    @ObservedObject var manager: HouseholdManager

    @State private var members: [HouseholdMember] = []
    @State private var nicknames: [UUID: String] = [:]
    @State private var hiddenUsers: Set<UUID> = []

    @State private var isLoadingMembers = false
    @State private var selectedMember: HouseholdMember?
    @State private var showingMemberOptions = false
    @State private var showingLeaveConfirmation = false
    @State private var showingRenameSheet = false

    var visibleMembers: [HouseholdMember] {
        members.filter { member in
            !hiddenUsers.contains(member.userId)
        }
    }

    var body: some View {

        Form {

            // MARK: - Household

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


            // MARK: - Members

            Section("Members") {

                if isLoadingMembers {

                    HStack {
                        Spacer()

                        ProgressView()

                        Spacer()
                    }

                } else if visibleMembers.isEmpty {

                    Text("No members to display.")
                        .foregroundColor(.gray)

                } else {

                    ForEach(visibleMembers) { member in

                        Button {

                            selectedMember = member
                            showingMemberOptions = true

                        } label: {

                            HStack {

                                Text(displayName(for: member))
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }


            // MARK: - Hidden Members

            if !hiddenUsers.isEmpty {

                Section("Hidden Members") {

                    ForEach(
                        members.filter {
                            hiddenUsers.contains($0.userId)
                        }
                    ) { member in

                        Button {

                            Task {
                                await unhide(member)
                            }

                        } label: {

                            HStack {

                                Text(displayName(for: member))
                                    .foregroundColor(.primary)

                                Spacer()

                                Text("Show")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }


            // MARK: - Leave

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

        .task {
            await loadMembers()
        }

        // MARK: - Member Options

        .confirmationDialog(
            memberOptionsTitle,
            isPresented: $showingMemberOptions,
            titleVisibility: .visible
        ) {

            if let selectedMember {

                Button("Change Name") {
                    showingRenameSheet = true
                }

                if hiddenUsers.contains(selectedMember.userId) {

                    Button("Show User") {

                        Task {
                            await unhide(selectedMember)
                        }
                    }

                } else {

                    Button(
                        "Hide from View",
                        role: .destructive
                    ) {

                        Task {
                            await hide(selectedMember)
                        }
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        }

        // MARK: - Leave Confirmation

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

        // MARK: - Rename Sheet

        .sheet(
            isPresented: $showingRenameSheet
        ) {

            if let selectedMember {

                RenameMemberView(
                    currentName: displayName(
                        for: selectedMember
                    )
                ) { newName in

                    Task {

                        let success = await manager.setNickname(
                            targetUserId: selectedMember.userId,
                            nickname: newName
                        )

                        if success {

                            if newName.isEmpty {
                                nicknames[
                                    selectedMember.userId
                                ] = nil
                            } else {
                                nicknames[
                                    selectedMember.userId
                                ] = newName
                            }
                        }
                    }
                }
            }
        }
    }


    // MARK: - Member Options Title

    private var memberOptionsTitle: String {

        guard let selectedMember else {
            return "Member"
        }

        return displayName(for: selectedMember)
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

        members = await manager.fetchHouseholdMembers(
            householdId: household.id
        )

        nicknames = await manager.fetchNicknames()

        hiddenUsers = await manager.fetchHiddenUsers()

        isLoadingMembers = false
    }


    // MARK: - Hide

    private func hide(
        _ member: HouseholdMember
    ) async {

        let success = await manager.hideUser(
            targetUserId: member.userId
        )

        if success {
            hiddenUsers.insert(member.userId)
        }
    }


    // MARK: - Unhide

    private func unhide(
        _ member: HouseholdMember
    ) async {

        let success = await manager.unhideUser(
            targetUserId: member.userId
        )

        if success {
            hiddenUsers.remove(member.userId)
        }
    }


    // MARK: - Leave

    private func leaveHousehold() async {

        _ = await manager.leaveHousehold(
            householdId: household.id
        )
    }
}