import SwiftUI

/// The preferences screen reached from the side menu. Backed by
/// user_preferences (display name, photo rotation interval, whether to show
/// your own photos on your own display) and hidden_users (which household
/// members you don't want to see on your display).
struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var intervalMinutes: Double = 5
    @State private var showOwnImage: Bool = true

    @State private var householdMembers: [HouseholdUser] = []
    @State private var hiddenUserIds: Set<UUID> = []
    @State private var nicknames: [UUID: String] = [:]

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task { await load() }
    }

    private var form: some View {
        Form {
            Section("Display") {
                TextField("Name shown on display", text: $displayName)
            }

            Section("Photo rotation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Change photo every \(Int(intervalMinutes)) min")
                    Slider(value: $intervalMinutes, in: 1...60, step: 1)
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Show my own photos on my display", isOn: $showOwnImage)
            }

            Section("Hide & rename family members") {
                if householdMembers.isEmpty {
                    Text("No other household members yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(householdMembers) { member in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(displayLabel(for: member), isOn: visibilityBinding(for: member.id))
                            TextField("Nickname (e.g. Dad)", text: nicknameBinding(for: member.id))
                                .textFieldStyle(.roundedBorder)
                                .font(.footnote)
                                .autocorrectionDisabled()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
        }
    }

    /// True = shown on this user's display, false = hidden. Toggling writes
    /// straight through to hidden_users immediately, separately from Save
    /// (which only covers the user_preferences fields and nicknames).
    private func visibilityBinding(for memberId: UUID) -> Binding<Bool> {
        Binding(
            get: { !hiddenUserIds.contains(memberId) },
            set: { isShown in
                Task { await toggleVisibility(for: memberId, show: isShown) }
            }
        )
    }

    private func nicknameBinding(for memberId: UUID) -> Binding<String> {
        Binding(
            get: { nicknames[memberId] ?? "" },
            set: { nicknames[memberId] = $0 }
        )
    }

    /// What to show as this member's label right now — their nickname if
    /// one's been typed, otherwise their real name.
    private func displayLabel(for member: HouseholdUser) -> String {
        let nickname = (nicknames[member.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return nickname.isEmpty ? (member.name ?? "Unnamed") : nickname
    }

    private func load() async {
        guard let userId = auth.userId else { return }
        isLoading = true
        errorMessage = nil
        do {
            let prefs = try await SupabaseManager.shared.fetchPreferences(userId: userId)
            displayName = prefs.displayName ?? ""
            intervalMinutes = max(1, (Double(prefs.imageIntervalSeconds) / 60).rounded())
            showOwnImage = prefs.showOwnImage

            householdMembers = try await SupabaseManager.shared.fetchHouseholdMembers(excluding: userId)
            hiddenUserIds = try await SupabaseManager.shared.fetchHiddenUserIds(userId: userId)
            nicknames = try await SupabaseManager.shared.fetchNicknames(viewerId: userId)
        } catch {
            errorMessage = "Couldn't load settings."
        }
        isLoading = false
    }

    private func save() {
        guard let userId = auth.userId else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = UpdatedPreferences(
                    displayName: displayName.isEmpty ? nil : displayName,
                    imageIntervalSeconds: Int(intervalMinutes) * 60,
                    showOwnImage: showOwnImage
                )
                try await SupabaseManager.shared.updatePreferences(userId: userId, preferences: updated)

                for member in householdMembers {
                    let value = nicknames[member.id] ?? ""
                    try await SupabaseManager.shared.setNickname(viewerId: userId, targetId: member.id, nickname: value)
                }

                isSaving = false
                dismiss()
            } catch {
                errorMessage = "Couldn't save settings."
                isSaving = false
            }
        }
    }

    private func toggleVisibility(for memberId: UUID, show: Bool) async {
        guard let userId = auth.userId else { return }
        do {
            if show {
                try await SupabaseManager.shared.unhideUser(userId: userId, hiddenUserId: memberId)
                hiddenUserIds.remove(memberId)
            } else {
                try await SupabaseManager.shared.hideUser(userId: userId, hiddenUserId: memberId)
                hiddenUserIds.insert(memberId)
            }
        } catch {
            errorMessage = "Couldn't update visibility."
        }
    }
}
