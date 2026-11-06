import SwiftUI

struct HouseholdMembersView: View {

    let household: Household
    @ObservedObject var manager: HouseholdManager
    @Environment(\.dismiss) private var dismiss

    @State private var members: [HouseholdMember] = []
    @State private var nicknames: [UUID: String] = [:]
    
    @State private var editingMemberId: UUID? = nil
    @State private var draftNickname: String = ""
    
    @FocusState private var focusedMemberId: UUID?

    @State private var isLoadingMembers = false
    @State private var showingLeaveConfirmation = false

    var otherMembers: [HouseholdMember] {
        guard let currentUserId = manager.currentUserId else { return [] }
        return members.filter { $0.userId != currentUserId }
    }

    var body: some View {
        Form {
            if let error = manager.errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }

            Section {
                HStack {
                    Text("Join Code")
                    Spacer()
                    Text(household.joinCode)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

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
                            if editingMemberId == member.userId {
                                TextField("Name", text: $draftNickname)
                                    .foregroundColor(.primary)
                                    .focused($focusedMemberId, equals: member.userId)
                                    .onSubmit { saveNickname(for: member) }
                                
                                Spacer()
                                
                                Button {
                                    saveNickname(for: member)
                                } label: {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                
                            } else {
                                Text(displayName(for: member))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button {
                                    editingMemberId = member.userId
                                    draftNickname = displayName(for: member)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        focusedMemberId = member.userId
                                    }
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Leave Household", role: .destructive) {
                    showingLeaveConfirmation = true
                }
            }
        }
        .navigationTitle(household.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMembers() }
        .alert("Leave Household?", isPresented: $showingLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                Task { await leaveHousehold() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be removed from \(household.name).")
        }
    }

    private func displayName(for member: HouseholdMember) -> String {
        if let nickname = nicknames[member.userId], !nickname.isEmpty {
            return nickname
        }
        return member.name ?? "Unnamed User"
    }

    private func loadMembers() async {
        isLoadingMembers = true
        let loadedMembers = await manager.fetchHouseholdMembers(householdId: household.id)
        let loadedNicknames = await manager.fetchNicknames()
        members = loadedMembers
        nicknames = loadedNicknames
        isLoadingMembers = false
    }
    
    private func saveNickname(for member: HouseholdMember) {
        focusedMemberId = nil
        Task {
            let success = await manager.setNickname(targetUserId: member.userId, nickname: draftNickname)
            if success {
                await MainActor.run {
                    nicknames[member.userId] = draftNickname
                    editingMemberId = nil
                }
            } else {
                await loadMembers()
                await MainActor.run { editingMemberId = nil }
            }
        }
    }

    private func leaveHousehold() async {
        let success = await manager.leaveHousehold(householdId: household.id)
        
        // Only dismiss the screen if the call was successful
        if success {
            await MainActor.run { dismiss() }
        }
    }
}