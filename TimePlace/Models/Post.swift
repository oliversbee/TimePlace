import Foundation

struct Post: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let imageUrl: String
    let takenAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case imageUrl = "image_url"
        case takenAt = "taken_at"
        case createdAt = "created_at"
    }
}

/// Payload sent when inserting a new post row.
struct NewPost: Encodable {
    let userId: UUID
    let imageUrl: String
    let takenAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case imageUrl = "image_url"
        case takenAt = "taken_at"
    }
}
