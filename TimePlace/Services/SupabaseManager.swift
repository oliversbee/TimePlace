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

    /// Uploads the composited photo to the "posts" storage bucket
    /// and inserts a matching row into the "posts" table.
    func uploadPost(userId: UUID, image: UIImage) async throws {
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
            .upload(path: fileName, file: data, options: FileOptions(contentType: "image/jpeg"))

        let publicURL = try client.storage.from("posts").getPublicURL(path: fileName)

        let newPost = NewPost(userId: userId, imageUrl: publicURL.absoluteString, takenAt: Date())

        try await client
            .from("posts")
            .insert(newPost)
            .execute()
    }
}
