import Foundation
import UIKit
import Supabase

/// Thin wrapper around the Supabase client used across the app.
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }

    // MARK: - Images

    /// Uploads a captured photo to the "posts" storage bucket.
    ///
    /// One mode:
    ///     mainImage -> one uploaded image -> one database row
    ///
    /// Both mode:
    ///     mainImage + secondaryImage
    ///     -> combined into ONE image
    ///     -> one uploaded image
    ///     -> one database row
    ///
    /// The app ONLY uploads images.
    /// It never downloads images from Supabase.
    func uploadImages(
        userId: UUID,
        mainImage: UIImage,
        secondaryImage: UIImage?
    ) async throws {

        let takenAt = Date()

        // If Both mode was selected, combine the two images
        // into a single image before uploading.
        let imageToUpload: UIImage

        if let secondaryImage {
            imageToUpload = combineImages(
                main: mainImage,
                secondary: secondaryImage
            )
        } else {
            imageToUpload = mainImage
        }

        // Upload exactly ONE file.
        let imagePath = try await uploadImage(
            imageToUpload,
            userId: userId
        )

        // Insert exactly ONE database row.
        try await insertImageRow(
            userId: userId,
            imagePath: imagePath,
            takenAt: takenAt
        )
    }

    // MARK: Upload Image

    private func uploadImage(
        _ image: UIImage,
        userId: UUID
    ) async throws -> String {

        guard let data = image.jpegData(
            compressionQuality: 0.85
        ) else {
            throw NSError(
                domain: "SupabaseManager",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not encode captured photo."
                ]
            )
        }

        // Store images inside a folder belonging to the user.
        //
        // Example:
        //
        // posts/
        //   0fb6255a.../
        //       4A7B...jpg
        //
        let fileName =
            "\(userId.uuidString)/\(UUID().uuidString).jpg"

        try await client.storage
            .from("posts")
            .upload(
                fileName,
                data: data,
                options: FileOptions(
                    contentType: "image/jpeg"
                )
            )

        // IMPORTANT:
        //
        // Do NOT call getPublicURL().
        //
        // The Storage bucket is private.
        // We store the Storage path in the database.
        return fileName
    }

    // MARK: Insert Image Row

    private func insertImageRow(
        userId: UUID,
        imagePath: String,
        takenAt: Date
    ) async throws {

        let newImage = NewImage(
            userId: userId,
            imagePath: imagePath,
            takenAt: takenAt
        )

        try await client
            .from("images")
            .insert(newImage)
            .execute()
    }

    // MARK: Combine Images

    /// Combines the main and secondary camera images into
    /// a single image.
    ///
    /// The main image fills the canvas.
    /// The secondary image is placed in the bottom-right.
    private func combineImages(
        main: UIImage,
        secondary: UIImage
    ) -> UIImage {

        let canvasSize = main.size

        let renderer = UIGraphicsImageRenderer(
            size: canvasSize
        )

        return renderer.image { context in

            let canvas = CGRect(
                origin: .zero,
                size: canvasSize
            )

            // ------------------------------------------------
            // MAIN IMAGE
            // ------------------------------------------------

            main.draw(in: canvas)

            // ------------------------------------------------
            // SECONDARY IMAGE
            // ------------------------------------------------

            let overlayWidth =
                min(canvasSize.width * 0.25, 360)

            let overlayHeight =
                overlayWidth * (160.0 / 120.0)

            let margin =
                canvasSize.width * 0.04

            let overlayRect = CGRect(
                x: canvasSize.width
                    - overlayWidth
                    - margin,

                y: canvasSize.height
                    - overlayHeight
                    - margin,

                width: overlayWidth,
                height: overlayHeight
            )

            // Clip the secondary image to rounded corners.
            let roundedPath = UIBezierPath(
                roundedRect: overlayRect,
                cornerRadius: 16
            )

            roundedPath.addClip()

            secondary.draw(
                in: overlayRect
            )

            // ------------------------------------------------
            // BORDER
            // ------------------------------------------------

            context.cgContext.resetClip()

            let borderPath = UIBezierPath(
                roundedRect: overlayRect,
                cornerRadius: 16
            )

            borderPath.lineWidth = 6

            UIColor.white.setStroke()

            borderPath.stroke()
        }
    }

    // MARK: - Preferences

    func fetchPreferences(
        userId: UUID
    ) async throws -> UserPreferences? {

        let rows: [UserPreferences] = try await client
            .from("user_preferences")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    /// Saves the complete preference row.
    /// Upsert means this works whether the user's
    /// preferences row already exists or needs to be created.
    func updatePreferences(
        userId: UUID,
        preferences: UpdatedPreferences
    ) async throws {

        struct PreferencesPayload: Encodable {
            let userId: UUID
            let displayName: String?
            let imageIntervalSeconds: Int
            let showOwnImage: Bool

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case displayName = "display_name"
                case imageIntervalSeconds =
                    "image_interval_seconds"
                case showOwnImage = "show_own_image"
            }
        }

        let payload = PreferencesPayload(
            userId: userId,
            displayName: preferences.displayName,
            imageIntervalSeconds:
                preferences.imageIntervalSeconds,
            showOwnImage:
                preferences.showOwnImage
        )

        try await client
            .from("user_preferences")
            .upsert(
                payload,
                onConflict: "user_id"
            )
            .execute()
    }

    // MARK: - Hidden Users

    func fetchHouseholdMembers(
        excluding userId: UUID
    ) async throws -> [HouseholdUser] {

        let all: [HouseholdUser] = try await client
            .from("users")
            .select("id, name")
            .execute()
            .value

        return all.filter {
            $0.id != userId
        }
    }

    func fetchHiddenUserIds(
        userId: UUID
    ) async throws -> Set<UUID> {

        let rows: [HiddenUser] = try await client
            .from("hidden_users")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        return Set(
            rows.map {
                $0.hiddenUserId
            }
        )
    }

    func hideUser(
        userId: UUID,
        hiddenUserId: UUID
    ) async throws {

        let row = NewHiddenUser(
            userId: userId,
            hiddenUserId: hiddenUserId
        )

        try await client
            .from("hidden_users")
            .insert(row)
            .execute()
    }

    func unhideUser(
        userId: UUID,
        hiddenUserId: UUID
    ) async throws {

        try await client
            .from("hidden_users")
            .delete()
            .eq("user_id", value: userId)
            .eq("hidden_user_id", value: hiddenUserId)
            .execute()
    }

    // MARK: - Nicknames

    /// What viewerId privately calls each other user,
    /// keyed by target id.
    ///
    /// Missing entries mean:
    /// "no nickname set — use their real name."
    func fetchNicknames(
        viewerId: UUID
    ) async throws -> [UUID: String] {

        let rows: [NicknameRow] = try await client
            .from("nicknames")
            .select()
            .eq("viewer_id", value: viewerId)
            .execute()
            .value

        return Dictionary(
            uniqueKeysWithValues:
                rows.map {
                    ($0.targetId, $0.nickname)
                }
        )
    }

    /// Setting an empty/blank nickname clears it.
    func setNickname(
        viewerId: UUID,
        targetId: UUID,
        nickname: String
    ) async throws {

        let trimmed =
            nickname.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            try await clearNickname(
                viewerId: viewerId,
                targetId: targetId
            )
            return
        }

        let row = UpsertNickname(
            viewerId: viewerId,
            targetId: targetId,
            nickname: trimmed
        )

        try await client
            .from("nicknames")
            .upsert(
                row,
                onConflict: "viewer_id,target_id"
            )
            .execute()
    }

    func clearNickname(
        viewerId: UUID,
        targetId: UUID
    ) async throws {

        try await client
            .from("nicknames")
            .delete()
            .eq("viewer_id", value: viewerId)
            .eq("target_id", value: targetId)
            .execute()
    }
}