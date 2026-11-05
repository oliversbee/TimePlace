import SwiftUI

struct HouseholdMembersView: View {

    let household: Household

    @ObservedObject var manager: HouseholdManager
    
    @Environment(\.dismiss) private var dismiss

    @State private var members: [HouseholdMember] = []
    @State private var nicknames: [UUID: String] = [:]
    
    // Tracks which member is currently being edited and their draft name
    @State private var editingMemberId: UUID? = nil
    @State private var draftNickname: String = ""
    
    // Report State
    @State private var memberToReport: HouseholdMember?
    @State private var showReportAlert = false
    @State private var reportReason = ""
    
    // Automatically manages the keyboard focus
    @FocusState private var focusedMemberId: UUID?

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
                        .font(.system(.body, design: .monospaced))
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
                            if editingMemberId == member.userId {
                                // Editing Mode
                                TextField("Name", text: $draftNickname)
                                    .foregroundColor(.primary)
                                    .focused($focusedMemberId, equals: member.userId)
                                    .onSubmit {
                                        saveNickname(for: member)
                                    }
                                
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
                                // View Mode
                                Text(displayName(for: member))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button {
                                    editingMemberId = member.userId
                                    draftNickname = displayName(for: member)
                                    
                                    // Slight delay ensures the TextField is rendered before focusing
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
                        // NEW: Unobtrusive swipe actions for App Store Guideline 1.2
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                memberToReport = member
                                reportReason = ""
                                showReportAlert = true
                            } label: {
                                Label("Report", systemImage: "exclamationmark.bubble")
                            }
                            
                            Button {
                                Task {
                                    _ = await manager.hideUser(targetUserId: member.userId)
                                }
                            } label: {
                                Label("Block", systemImage: "hand.raised.slash")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }

            // MARK: Leave
            Section {
                Button("Leave Household", role: .destructive) {
                    showingLeaveConfirmation = true
                }
            }
        }
        .navigationTitle(household.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMembers()
        }
        .alert("Leave Household?", isPresented: $showingLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                Task {
                    await leaveHousehold()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be removed from \(household.name).")
        }
        // NEW: Report Alert
        .alert("Report User", isPresented: $showReportAlert) {
            TextField("Reason", text: $reportReason)
            Button("Cancel", role: .cancel) { memberToReport = nil }
            Button("Submit", role: .destructive) {
                submitReport()
            }
        } message: {
            Text("This will privately notify the developer. You can also block this user by swiping left and tapping Block.")
        }
    }

    // MARK: - Display Name

    private func displayName(for member: HouseholdMember) -> String {
        if let nickname = nicknames[member.userId], !nickname.isEmpty {
            return nickname
        }
        return member.name ?? "Unnamed User"
    }

    // MARK: - Load Members

    private func loadMembers() async {
        isLoadingMembers = true

        let loadedMembers = await manager.fetchHouseholdMembers(householdId: household.id)
        let loadedNicknames = await manager.fetchNicknames()

        members = loadedMembers
        nicknames = loadedNicknames

        isLoadingMembers = false
    }

    // MARK: - Save Nickname
    
    private func saveNickname(for member: HouseholdMember) {
        // Dismiss keyboard
        focusedMemberId = nil
        
        Task {
            let success = await manager.setNickname(
                targetUserId: member.userId,
                nickname: draftNickname
            )
            
            if success {
                await MainActor.run {
                    nicknames[member.userId] = draftNickname
                    editingMemberId = nil // Reverts the arrow back to the pencil
                }
            } else {
                // Optionally reload on failure to revert state
                await loadMembers()
                await MainActor.run {
                    editingMemberId = nil
                }
            }
        }
    }

    // MARK: - Submit Report
    private func submitReport() {
        guard let userToReport = memberToReport, let currentUserId = manager.currentUserId else { return }
        
        let finalReason = reportReason.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            try? await SupabaseManager.shared.client.from("reports").insert(
                NewReport(
                    reporter_id: currentUserId,
                    reported_user_id: userToReport.userId,
                    reason: finalReason.isEmpty ? "No reason provided" : finalReason
                )
            ).execute()
            
            await MainActor.run {
                memberToReport = nil
            }
        }
    }

    // MARK: - Leave

    private func leaveHousehold() async {
        _ = await manager.leaveHousehold(householdId: household.id)
        
        await MainActor.run {
            dismiss()
        }
    }
}

// Struct for the Report API Call
struct NewReport: Encodable {
    let reporter_id: UUID
    let reported_user_id: UUID
    let reason: String
}