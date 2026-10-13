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

    /// Uploads a captured photo to the "posts" Storage bucket.
    ///
    /// One mode:
    ///     mainImage -> resized to 800x480 -> one uploaded image
    ///     -> one database row
    ///
    /// Both mode:
    ///     mainImage + secondaryImage
    ///     -> combined into ONE image
    ///     -> resized to 800x480
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

        // Combine the images first if Both mode was selected.
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
        // The image is resized to 800x480 inside uploadImage().
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

    // MARK: - Upload Image

    private func uploadImage(
        _ image: UIImage,
        userId: UUID
    ) async throws -> String {

        // Prepare a display-ready image before uploading.
        let displayImage = prepareForDisplay(image)

        guard let data = displayImage.jpegData(
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
        //   user-id/
        //       image-id.jpg
        //
        let fileName =
            "\(userId.uuidString.lowercased())/\(UUID().uuidString).jpg"

        try await client.storage
            .from("posts")
            .upload(
                fileName,
                data: data,
                options: FileOptions(
                    contentType: "image/jpeg"
                )
            )

        // Keep the existing private Storage bucket behaviour.
        // Store the Storage path in the database.
        return fileName
    }

    // MARK: - Prepare Image for Inky Frame

    /// Produces an exact 800x480 pixel JPEG-ready image.
    ///
    /// The original photo is kept entirely visible.
    /// Its proportions are preserved, and unused space is white.
    ///
    /// Setting renderer scale to 1 ensures the output is
    /// 800x480 pixels rather than 800x480 UIKit points.
    
    // MARK: - Prepare Image for Inky Frame

    /// Produces an exact 800x480 landscape JPEG.
    ///
    /// Portrait photos are rotated 90 degrees to fit the
    /// landscape Inky Frame. The complete image is preserved.
    ///
    /// The output is exactly 800x480 pixels.
    private func prepareForDisplay(
        _ image: UIImage
    ) -> UIImage {

        let targetSize = CGSize(
            width: 800,
            height: 480
        )

        // Apply the original image's orientation to its pixels.
        let normalisedImage = image.fixedOrientation()

        guard
            normalisedImage.size.width > 0,
            normalisedImage.size.height > 0
        else {
            return normalisedImage
        }

        let sourceWidth = normalisedImage.size.width
        let sourceHeight = normalisedImage.size.height

        // Rotate portrait images so their dimensions become landscape.
        let shouldRotate = sourceHeight > sourceWidth

        let orientedSize: CGSize

        if shouldRotate {
            orientedSize = CGSize(
                width: sourceHeight,
                height: sourceWidth
            )
        } else {
            orientedSize = normalisedImage.size
        }

        // Fit the complete, rotated image inside 800x480.
        // This preserves the aspect ratio and prevents cropping.
        let scale = min(
            targetSize.width / orientedSize.width,
            targetSize.height / orientedSize.height
        )

        let fittedWidth = orientedSize.width * scale
        let fittedHeight = orientedSize.height * scale

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        )

        return renderer.image { context in

            // White background for any unused space.
            UIColor.white.setFill()
            context.fill(
                CGRect(
                    origin: .zero,
                    size: targetSize
                )
            )

            context.cgContext.saveGState()

            if shouldRotate {
                // Rotate the canvas 90 degrees clockwise.
                context.cgContext.translateBy(
                    x: targetSize.width,
                    y: 0
                )
                context.cgContext.rotate(
                    by: .pi / 2
                )

                // After rotation, the canvas is effectively 480x800.
                let rotatedRect = CGRect(
                    x: (targetSize.height - fittedHeight) / 2,
                    y: (targetSize.width - fittedWidth) / 2,
                    width: fittedHeight,
                    height: fittedWidth
                )

                normalisedImage.draw(in: rotatedRect)
            } else {
                // Landscape photos are fitted without rotation.
                let imageRect = CGRect(
                    x: (targetSize.width - fittedWidth) / 2,
                    y: (targetSize.height - fittedHeight) / 2,
                    width: fittedWidth,
                    height: fittedHeight
                )

                normalisedImage.draw(in: imageRect)
            }

            context.cgContext.restoreGState()
        }
    }


    // MARK: - Insert Image Row

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

    // MARK: - Combine Images

    /// Combines the main and secondary camera images into
    /// a single image.
    ///
    /// The main image fills the canvas.
    /// The secondary image is placed in the bottom-right
    /// while preserving its original aspect ratio.
    ///
    /// The completed composite is resized to 800x480
    /// immediately before uploading.
    private func combineImages(
        main: UIImage,
        secondary: UIImage
    ) -> UIImage {

        let mainImage = main.fixedOrientation()
        let secondaryImage = secondary.fixedOrientation()

        let canvasSize = mainImage.size

        let renderer = UIGraphicsImageRenderer(
            size: canvasSize
        )

        return renderer.image { context in

            let canvas = CGRect(
                origin: .zero,
                size: canvasSize
            )

            // Main image.
            mainImage.draw(in: canvas)

            // Secondary image inset.
            let overlayWidth =
                min(canvasSize.width * 0.25, 360)

            let secondaryAspectRatio =
                secondaryImage.size.height /
                max(secondaryImage.size.width, 1)

            let overlayHeight =
                overlayWidth * secondaryAspectRatio

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

            // Clip the inset to rounded corners.
            let roundedPath = UIBezierPath(
                roundedRect: overlayRect,
                cornerRadius: 16
            )

            context.cgContext.saveGState()
            roundedPath.addClip()

            secondaryImage.draw(in: overlayRect)

            context.cgContext.restoreGState()

            // White border around the inset.
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
    /// Upsert works whether the preferences row exists or
    /// needs to be created.
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

// MARK: - UIImage Orientation

extension UIImage {

    /// Returns an image with its orientation physically rendered
    /// into the pixels rather than stored only as orientation metadata.
    func fixedOrientation() -> UIImage {

        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(
            size: size,
            format: format
        )

        return renderer.image { _ in
            draw(
                in: CGRect(
                    origin: .zero,
                    size: size
                )
            )
        }
    }
}