import Foundation
import Supabase

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    let name: String
    var householdIds: Set<UUID> = []

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var showOwnImage: Bool = true
    @Published var imageIntervalSeconds: Int = 300
    @Published var familyMembers: [FamilyMember] = []
    @Published var hiddenUserIds: Set<UUID> = []
    @Published var nicknames: [UUID: String] = [:]

    @Published var selectedMemberForNickname: FamilyMember?
    @Published var tempNicknameText: String = ""
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared

    // MARK: - Load

    func loadData(currentUserId: UUID) async {
        errorMessage = nil

        do {
            // Load the user's saved preferences.
            let preferences = try await supabase.fetchPreferences(userId: currentUserId)

            displayName = preferences.displayName ?? ""
            showOwnImage = preferences.showOwnImage
            imageIntervalSeconds = preferences.imageIntervalSeconds

            // Load the other family members and the user's per-member settings.
            familyMembers = try await supabase
                .fetchHouseholdMembers(excluding: currentUserId)
                .map { FamilyMember(id: $0.id, name: $0.name ?? "") }

            hiddenUserIds = try await supabase.fetchHiddenUserIds(userId: currentUserId)
            nicknames = try await supabase.fetchNicknames(viewerId: currentUserId)
        } catch {
            errorMessage = "Failed to load preferences: \(error.localizedDescription)"
        }
    }

    // MARK: - Save

    func savePreferences(currentUserId: UUID) async {
        isSaving = true
        errorMessage = nil

        let preferences = UpdatedPreferences(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            imageIntervalSeconds: imageIntervalSeconds,
            showOwnImage: showOwnImage
        )

        do {
            try await supabase.updatePreferences(
                userId: currentUserId,
                preferences: preferences
            )
        } catch {
            errorMessage = "Failed to save preferences: \(error.localizedDescription)"
        }

        isSaving = false
    }

    // MARK: - Hidden users

    func toggleHideUser(currentUserId: UUID, familyUserId: UUID) async {
        errorMessage = nil

        do {
            if hiddenUserIds.contains(familyUserId) {
                try await supabase.unhideUser(
                    userId: currentUserId,
                    hiddenUserId: familyUserId
                )
                hiddenUserIds.remove(familyUserId)
            } else {
                try await supabase.hideUser(
                    userId: currentUserId,
                    hiddenUserId: familyUserId
                )
                hiddenUserIds.insert(familyUserId)
            }
        } catch {
            errorMessage = "Failed to update hidden users: \(error.localizedDescription)"
        }
    }

    // MARK: - Nicknames

    func saveNickname(viewerId: UUID, targetId: UUID, nickname: String) async {
        errorMessage = nil

        do {
            try await supabase.setNickname(
                viewerId: viewerId,
                targetId: targetId,
                nickname: nickname
            )

            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                nicknames.removeValue(forKey: targetId)
            } else {
                nicknames[targetId] = trimmed
            }
        } catch {
            errorMessage = "Failed to save nickname: \(error.localizedDescription)"
        }
    }
}