import SwiftUI

struct HouseholdMembersView: View {

    let household: Household
    @ObservedObject var manager: HouseholdManager
    @Environment(\.dismiss) private var dismiss

    @State private var members: [HouseholdMember] = []
    @State private var nicknames: [UUID: String] = [:]
    
    @State private var editingMemberId: UUID? = nil
    @State private var draftNickname: String = ""
    
    // Safeguard State
    @State private var memberToReport: HouseholdMember?
    @State private var showReportAlert = false
    @State private var reportReason = ""
    @State private var showReportSuccess = false
    
    @State private var memberToBlock: HouseholdMember?
    @State private var showBlockConfirmation = false
    @State private var blockSuccessMessage: String?
    
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
                                
                                // NEW: Discoverable "..." menu for Report/Block
                                Menu {
                                    Button {
                                        memberToReport = member
                                        reportReason = ""
                                        showReportAlert = true
                                    } label: {
                                        Label("Report User", systemImage: "exclamationmark.bubble")
                                    }
                                    
                                    Button(role: .destructive) {
                                        memberToBlock = member
                                        showBlockConfirmation = true
                                    } label: {
                                        Label("Block User", systemImage: "hand.raised.slash")
                                    }
                                    
                                    Button {
                                        editingMemberId = member.userId
                                        draftNickname = displayName(for: member)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            focusedMemberId = member.userId
                                        }
                                    } label: {
                                        Label("Edit Name", systemImage: "pencil")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        // Keep swipe actions as a secondary method
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                memberToReport = member
                                reportReason = ""
                                showReportAlert = true
                            } label: {
                                Label("Report", systemImage: "exclamationmark.bubble")
                            }
                            
                            Button {
                                memberToBlock = member
                                showBlockConfirmation = true
                            } label: {
                                Label("Block", systemImage: "hand.raised.slash")
                            }
                            .tint(.orange)
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
        
        // Leave Alert
        .alert("Leave Household?", isPresented: $showingLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                Task { await leaveHousehold() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be removed from \(household.name).")
        }
        
        // Report Alert
        .alert("Report User", isPresented: $showReportAlert) {
            TextField("Reason", text: $reportReason)
            Button("Cancel", role: .cancel) { memberToReport = nil }
            Button("Submit", role: .destructive) { submitReport() }
        } message: {
            Text("This will privately notify the developer. You can also block this user.")
        }
        
        // Block Confirmation
        .confirmationDialog("Block User?", isPresented: $showBlockConfirmation, titleVisibility: .visible) {
            Button("Block \(memberToBlock?.name ?? "User")", role: .destructive) {
                if let userToBlock = memberToBlock {
                    Task {
                        let success = await manager.hideUser(targetUserId: userToBlock.userId)
                        if success {
                            blockSuccessMessage = "\(userToBlock.name ?? "User") has been blocked. Their photos will no longer appear on your frame."
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { memberToBlock = nil }
        } message: {
            Text("Their photos will no longer be shown on your display.")
        }
        
        // Report Success Alert
        .alert("Report Sent", isPresented: $showReportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you. We will review this report shortly.")
        }
        
        // Block Success Alert
        .alert("User Blocked", isPresented: Binding(
            get: { blockSuccessMessage != nil },
            set: { if !$0 { blockSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(blockSuccessMessage ?? "")
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

    private func submitReport() {
        guard let userToReport = memberToReport, let currentUserId = manager.currentUserId else { return }
        let finalReason = reportReason.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                try await SupabaseManager.shared.client.from("reports").insert(
                    NewReport(
                        reporter_id: currentUserId,
                        reported_user_id: userToReport.userId,
                        reason: finalReason.isEmpty ? "No reason provided" : finalReason
                    )
                ).execute()
                
                await MainActor.run {
                    memberToReport = nil
                    showReportSuccess = true
                }
            } catch {
                await MainActor.run {
                    memberToReport = nil
                    // Re-use manager error message for failure
                    manager.errorMessage = "Couldn't send your report, please try again."
                }
            }
        }
    }

    private func leaveHousehold() async {
        let success = await manager.leaveHousehold(householdId: household.id)
        if success {
            await MainActor.run { dismiss() }
        }
    }
}

struct NewReport: Encodable {
    let reporter_id: UUID
    let reported_user_id: UUID
    let reason: String
}