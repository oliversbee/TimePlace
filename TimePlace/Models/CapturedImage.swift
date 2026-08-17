import Foundation

/// Payload sent when inserting a new row into the "images" table.
/// A "Both" capture results in two of these being inserted (main + secondary);
/// a "One" capture results in one.
struct NewImage: Encodable {
    let userId: UUID
    let imageUrl: String
    let takenAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case imageUrl = "image_url"
        case takenAt = "taken_at"
    }
}
