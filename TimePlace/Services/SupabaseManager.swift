import Foundation
import UIKit
import Supabase

/// Thin wrapper around the Supabase client used across the app.
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey)
    }

    // MARK: - Images

    /// Uploads the captured photo(s) to the "posts" storage bucket and inserts
    /// a row per photo into the "images" table. A "Both" capture results in
    /// two rows (main + secondary); a "One" capture results in one.
    ///
    /// A database trigger keeps the "household" table's per-user "most recent
    /// image" pointer up to date automatically — nothing extra to do here.
    func uploadImages(userId: UUID, mainImage: UIImage, secondaryImage: UIImage?) async throws {
        let takenAt = Date()

        let mainURL = try await uploadImage(mainImage, userId: userId)
        try await insertImageRow(userId: userId, imageUrl: mainURL, takenAt: takenAt)

        if let secondaryImage {
            let secondaryURL = try await uploadImage(secondaryImage, userId: userId)
            try await insertImageRow(userId: userId, imageUrl: secondaryURL, takenAt: takenAt)
        }
    }

    private func uploadImage(_ image: UIImage, userId: UUID) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(
                domain: "SupabaseManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode captured photo."]
            )
        }

        // Store under a per-user folder so storage RLS policies can key off it.
        let fileName = "\(userId.uuidString)/\(UUID().uuidString).jpg"

        try await client.storage
            .from("posts")
            .upload(fileName, data: data, options: FileOptions(contentType: "image/jpeg"))

        let publicURL = try client.storage.from("posts").getPublicURL(path: fileName)
        return publicURL.absoluteString
    }

    private func insertImageRow(userId: UUID, imageUrl: String, takenAt: Date) async throws {
        let newImage = NewImage(userId: userId, imageUrl: imageUrl, takenAt: takenAt)
        try await client
            .from("images")
            .insert(newImage)
            .execute()
    }

    // MARK: - Preferences

    func fetchPreferences(userId: UUID) async throws -> UserPreferences {
        try await client
            .from("user_preferences")
            .select()
            .eq("user_id", value: userId)
            .single()
            .execute()
            .value
    }

    func updatePreferences(userId: UUID, preferences: UpdatedPreferences) async throws {
        try await client
            .from("user_preferences")
            .update(preferences)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - Hidden users

    /// Every other user in the household (there's only one household, so
    /// this is just everyone except the caller).
    func fetchHouseholdMembers(excluding userId: UUID) async throws -> [HouseholdUser] {
        let all: [HouseholdUser] = try await client
            .from("users")
            .select("id, name")
            .execute()
            .value
        return all.filter { $0.id != userId }
    }

    func fetchHiddenUserIds(userId: UUID) async throws -> Set<UUID> {
        let rows: [HiddenUser] = try await client
            .from("hidden_users")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        return Set(rows.map { $0.hiddenUserId })
    }

    func hideUser(userId: UUID, hiddenUserId: UUID) async throws {
        let row = NewHiddenUser(userId: userId, hiddenUserId: hiddenUserId)
        try await client
            .from("hidden_users")
            .insert(row)
            .execute()
    }

    func unhideUser(userId: UUID, hiddenUserId: UUID) async throws {
        try await client
            .from("hidden_users")
            .delete()
            .eq("user_id", value: userId)
            .eq("hidden_user_id", value: hiddenUserId)
            .execute()
    }

    // MARK: - Nicknames

    /// What `viewerId` privately calls each other user, keyed by target id.
    /// Missing entries mean "no nickname set — use their real name."
    func fetchNicknames(viewerId: UUID) async throws -> [UUID: String] {
        let rows: [NicknameRow] = try await client
            .from("nicknames")
            .select()
            .eq("viewer_id", value: viewerId)
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.targetId, $0.nickname) })
    }

    /// Setting an empty/blank nickname clears it (falls back to their real name).
    func setNickname(viewerId: UUID, targetId: UUID, nickname: String) async throws {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try await clearNickname(viewerId: viewerId, targetId: targetId)
            return
        }
        let row = UpsertNickname(viewerId: viewerId, targetId: targetId, nickname: trimmed)
        try await client
            .from("nicknames")
            .upsert(row, onConflict: "viewer_id,target_id")
            .execute()
    }

    func clearNickname(viewerId: UUID, targetId: UUID) async throws {
        try await client
            .from("nicknames")
            .delete()
            .eq("viewer_id", value: viewerId)
            .eq("target_id", value: targetId)
            .execute()
    }
}
