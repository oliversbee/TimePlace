import SwiftUI

struct PreferencesSettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var viewModel: SettingsViewModel

    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        Form {
            if let message = auth.errorMessage {
                Section {
                    Text(message).foregroundColor(.red)
                }
            }
            
            Section("Safety") {
                NavigationLink("Block & Report Users") {
                    BlockReportView()
                        .environmentObject(auth)
                        .environmentObject(viewModel) 
                }
            }
            
            Section("About") {
                NavigationLink("Legal & Support") {
                    LegalSupportView()
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    if isDeleting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Deleting…")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else {
                        Text("Delete Account")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
                .disabled(isDeleting)
            }
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await auth.deleteAccount()
                    isDeleting = false
                }
            }
        } message: {
            Text("This permanently deletes your account, your photos and your household memberships. This can't be undone.")
        }
    }
}

// MARK: - Block/Report View
struct BlockReportView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var auth: AuthManager
    
    @State private var memberToReport: FamilyMember?
    @State private var showReportAlert = false
    @State private var reportReason = ""
    @State private var showReportSuccess = false

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }
            
            Section(header: Text("All Users"), footer: Text("Blocking a user will prevent their photos from appearing on your display. Reporting will privately notify the developer.")) {
                if viewModel.familyMembers.isEmpty {
                    Text("No users found.").foregroundColor(.gray)
                } else {
                    ForEach(viewModel.familyMembers) { member in
                        HStack {
                            Text(member.name.isEmpty ? "Unnamed User" : member.name)
                            
                            if viewModel.hiddenUserIds.contains(member.id) {
                                Text("Blocked")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.leading, 4)
                            }
                            
                            Spacer()
                            
                            Menu {
                                Button {
                                    memberToReport = member
                                    reportReason = ""
                                    showReportAlert = true
                                } label: {
                                    Label("Report User", systemImage: "exclamationmark.bubble")
                                }
                                
                                if viewModel.hiddenUserIds.contains(member.id) {
                                    Button {
                                        Task {
                                            if let uid = auth.userId {
                                                await viewModel.toggleHideUser(currentUserId: uid, familyUserId: member.id)
                                            }
                                        }
                                    } label: {
                                        Label("Unblock User", systemImage: "checkmark.circle")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        Task {
                                            if let uid = auth.userId {
                                                await viewModel.toggleHideUser(currentUserId: uid, familyUserId: member.id)
                                            }
                                        }
                                    } label: {
                                        Label("Block User", systemImage: "hand.raised.slash")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Block & Report")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Report User", isPresented: $showReportAlert) {
            TextField("Reason", text: $reportReason)
            Button("Cancel", role: .cancel) { memberToReport = nil }
            Button("Submit", role: .destructive) {
                if let target = memberToReport, let uid = auth.userId {
                    Task {
                        let success = await viewModel.reportUser(
                            currentUserId: uid,
                            targetId: target.id,
                            reason: reportReason
                        )
                        if success {
                            showReportSuccess = true
                        }
                        memberToReport = nil
                    }
                }
            }
        } message: {
            Text("This will privately notify the developer.")
        }
        .alert("Report Sent", isPresented: $showReportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you. We will review this report shortly.")
        }
    }
}

struct LegalSupportView: View {
    var body: some View {
        Form {
            Section {
                Link("Terms of Service", destination: URL(string: "https://yourdomain.com/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://yourdomain.com/privacy")!)
            }
            
            Section {
                Link("Contact Support", destination: URL(string: "mailto:support@yourdomain.com")!)
            }
        }
        .navigationTitle("Legal & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}