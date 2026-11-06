import Foundation
import Supabase

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

struct NewReport: Encodable {
    let reporter_id: UUID
    let reported_user_id: UUID
    let reason: String
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var showOwnImage: Bool = true
    @Published var imageIntervalSeconds: Int = 300
    @Published var familyMembers: [FamilyMember] = []
    @Published var hiddenUserIds: Set<UUID> = []
    @Published var nicknames: [UUID: String] = [:]

    @Published var isSaving = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared

    // MARK: - Load

    func loadData(currentUserId: UUID) async {
        errorMessage = nil

        do {
            if let preferences = try await supabase.fetchPreferences(userId: currentUserId) {
                displayName = preferences.displayName ?? ""
                showOwnImage = preferences.showOwnImage
                imageIntervalSeconds = preferences.imageIntervalSeconds
            }
        } catch {
            errorMessage = "We couldn't load your preferences. Please check your connection."
            return
        }

        do {
            familyMembers = try await supabase
                .fetchHouseholdMembers(excluding: currentUserId)
                .map { FamilyMember(id: $0.id, name: $0.name ?? "") }
        } catch {
            errorMessage = "We couldn't load your family members."
        }

        do {
            hiddenUserIds = try await supabase.fetchHiddenUserIds(userId: currentUserId)
        } catch {
            errorMessage = "We couldn't load your hidden users."
        }

        do {
            nicknames = try await supabase.fetchNicknames(viewerId: currentUserId)
        } catch {
            errorMessage = "We couldn't load your nicknames."
        }
    }

    // MARK: - Save

    func savePreferences(currentUserId: UUID) async {
        isSaving = true
        errorMessage = nil

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        let preferences = UpdatedPreferences(
            displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName,
            imageIntervalSeconds: imageIntervalSeconds,
            showOwnImage: showOwnImage
        )

        do {
            try await supabase.updatePreferences(userId: currentUserId, preferences: preferences)
        } catch {
            errorMessage = "We couldn't save your preferences."
        }

        isSaving = false
    }

    // MARK: - Hidden users (Blocking)

    func toggleHideUser(currentUserId: UUID, familyUserId: UUID) async {
        errorMessage = nil

        do {
            if hiddenUserIds.contains(familyUserId) {
                try await supabase.unhideUser(userId: currentUserId, hiddenUserId: familyUserId)
                hiddenUserIds.remove(familyUserId)
            } else {
                try await supabase.hideUser(userId: currentUserId, hiddenUserId: familyUserId)
                hiddenUserIds.insert(familyUserId)
            }
        } catch {
            errorMessage = "We couldn't update the blocked status."
        }
    }

    // MARK: - Reporting

    func reportUser(currentUserId: UUID, targetId: UUID, reason: String) async -> Bool {
        let finalReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            try await supabase.client.from("reports").insert(
                NewReport(
                    reporter_id: currentUserId,
                    reported_user_id: targetId,
                    reason: finalReason.isEmpty ? "No reason provided" : finalReason
                )
            ).execute()
            return true
        } catch {
            errorMessage = "We couldn't send your report. Please try again."
            return false
        }
    }
}