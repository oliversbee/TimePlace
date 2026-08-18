import SwiftUI

struct DisplayConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthManager
    @StateObject private var viewModel = SettingsViewModel()

    let device: PairedDevice

    var body: some View {
        NavigationStack {
            Form {
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }

                Section("Display Identity") {
                    TextField("Screen Label (e.g. Kitchen Display)", text: $viewModel.displayName)
                }

                Section("Member Nicknames on Display") {
                    if viewModel.familyMembers.isEmpty {
                        Text("No household members found.").foregroundColor(.gray)
                    } else {
                        ForEach(viewModel.familyMembers) { member in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(member.name)
                                        .font(.subheadline)
                                    if let nickname = viewModel.nicknames[member.id], !nickname.isEmpty {
                                        Text("Shows as: \"\(nickname)\"")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                                Button {
                                    viewModel.selectedMemberForNickname = member
                                    viewModel.tempNicknameText = viewModel.nicknames[member.id] ?? ""
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }

                Section("Visible Members on Screen") {
                    ForEach(viewModel.familyMembers) { member in
                        Toggle(
                            "Show \(member.name)'s Photos",
                            isOn: Binding(
                                get: { !viewModel.hiddenUserIds.contains(member.id) },
                                set: { _ in
                                    if let userId = auth.userId {
                                        Task {
                                            await viewModel.toggleHideUser(currentUserId: userId, familyUserId: member.id)
                                        }
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .navigationTitle("Configure Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let userId = auth.userId {
                            Task {
                                await viewModel.savePreferences(currentUserId: userId)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .sheet(item: $viewModel.selectedMemberForNickname) { member in
                NavigationStack {
                    Form {
                        Section("Set Nickname for \(member.name)") {
                            TextField("Custom Nickname", text: $viewModel.tempNicknameText)
                        }
                    }
                    .navigationTitle("Edit Nickname")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { viewModel.selectedMemberForNickname = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if let userId = auth.userId {
                                    Task {
                                        await viewModel.saveNickname(
                                            viewerId: userId,
                                            targetId: member.id,
                                            nickname: viewModel.tempNicknameText
                                        )
                                        viewModel.selectedMemberForNickname = nil
                                    }
                                }
                            }
                        }
                    }
                }
                .presentationDetents([.height(200)])
            }
            .task {
                if let userId = auth.userId {
                    await viewModel.loadData(currentUserId: userId)
                    viewModel.displayName = device.name
                }
            }
        }
    }
}