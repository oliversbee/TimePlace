import Foundation

/// One row per user, as fetched from public.user_preferences.
struct UserPreferences: Codable {
    let userId: UUID
    var displayName: String?
    var imageIntervalSeconds: Int
    var showOwnImage: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case imageIntervalSeconds = "image_interval_seconds"
        case showOwnImage = "show_own_image"
    }
}

/// Payload for updating preferences — only the fields a user can change.
struct UpdatedPreferences: Encodable {
    var displayName: String?
    var imageIntervalSeconds: Int
    var showOwnImage: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case imageIntervalSeconds = "image_interval_seconds"
        case showOwnImage = "show_own_image"
    }
}

/// A household member as shown in the "hide family members" list.
struct HouseholdUser: Codable, Identifiable {
    let id: UUID
    let name: String?
}

/// One row from public.hidden_users.
struct HiddenUser: Codable {
    let userId: UUID
    let hiddenUserId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case hiddenUserId = "hidden_user_id"
    }
}

struct NewHiddenUser: Encodable {
    let userId: UUID
    let hiddenUserId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case hiddenUserId = "hidden_user_id"
    }
}

/// One row from public.nicknames — what `viewerId` privately calls `targetId`.
struct NicknameRow: Codable {
    let viewerId: UUID
    let targetId: UUID
    let nickname: String

    enum CodingKeys: String, CodingKey {
        case viewerId = "viewer_id"
        case targetId = "target_id"
        case nickname
    }
}

struct UpsertNickname: Encodable {
    let viewerId: UUID
    let targetId: UUID
    let nickname: String

    enum CodingKeys: String, CodingKey {
        case viewerId = "viewer_id"
        case targetId = "target_id"
        case nickname
    }
}
