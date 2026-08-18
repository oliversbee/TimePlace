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

    private let client = SupabaseManager.shared.client

    func loadData(currentUserId: UUID) async {
        // Load initial display settings & family member lists here
    }

    func savePreferences(currentUserId: UUID) async {
        isSaving = true
        // Save user preferences logic here
        isSaving = false
    }

    func toggleHideUser(currentUserId: UUID, familyUserId: UUID) async {
        if hiddenUserIds.contains(familyUserId) {
            hiddenUserIds.remove(familyUserId)
        } else {
            hiddenUserIds.insert(familyUserId)
        }
    }

    func saveNickname(viewerId: UUID, targetId: UUID, nickname: String) async {
        nicknames[targetId] = nickname
    }
}