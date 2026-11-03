import SwiftUI

struct PostPreviewView: View {
    @EnvironmentObject var auth: AuthManager

    let mainImage: UIImage

    /// nil when the user chose "One" camera mode.
    /// non-nil when the user chose "Both".
    let secondaryImage: UIImage?

    var onRetake: () -> Void
    var onUploaded: () -> Void

    @State private var isUploading = false
    @State private var errorMessage: String?

    // Unified corner radius for the main image, PiP, and buttons
    private let uniformCornerRadius: CGFloat = 24

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                
                // Error Banner (kept at the top if needed)
                if let errorMessage {
                    GlassStatusBanner(text: errorMessage)
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                }

                // =========================================================
                // IMAGE PREVIEW AREA
                // =========================================================
                ZStack(alignment: .bottomTrailing) {
                    
                    // Main Image
                    Image(uiImage: mainImage)
                        .resizable()
                        .scaledToFill()
                        // Allow the image to expand to fill available vertical space
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous))
                    
                    // Secondary PiP Image
                    if let secondaryImage {
                        secondaryImageView(image: secondaryImage)
                    }
                }
                // Reduced horizontal padding to make the image larger
                .padding(.horizontal, 16)
                // Reduced top padding to push the image higher
                .padding(.top, 40)
                
                Spacer(minLength: 20)
                
                // =========================================================
                // BOTTOM CONTROLS
                // =========================================================
                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
            }
        }
    }

    // =====================================================================
    // SECONDARY IMAGE
    // =====================================================================

    private func secondaryImageView(image: UIImage) -> some View {
        let maxWidth: CGFloat = 120
        let maxHeight: CGFloat = 160

        let imageWidth = image.size.width
        let imageHeight = image.size.height
        let aspectRatio = imageHeight / max(imageWidth, 1)

        let width = min(maxWidth, maxHeight / max(aspectRatio, 0.001))
        let height = width * aspectRatio

        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            // Use the uniform corner radius
            .clipShape(RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous)
                    .stroke(.white, lineWidth: 3.5)
            )
            .padding(20) 
    }

    // =====================================================================
    // CONTROLS
    // =====================================================================

    private var controls: some View {
        HStack(spacing: 16) {
            
            // Retake Button
            Button(action: onRetake) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .bold))
                    Text("Retake")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(white: 0.12))
                // Changed from Capsule to match the image's corner radius
                .clipShape(RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous))
            }
            .disabled(isUploading)
            .opacity(isUploading ? 0.5 : 1.0)

            // Upload Button
            Button {
                upload()
            } label: {
                Group {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .bold))
                            Text("Upload")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.55, blue: 0.25), // Light orange
                            Color(red: 0.9, green: 0.25, blue: 0.35)   // Coral red
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                // Changed from Capsule to match the image's corner radius
                .clipShape(RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous))
            }
            .disabled(isUploading)
            .opacity(isUploading ? 0.8 : 1.0)
        }
    }

    // =====================================================================
    // UPLOAD
    // =====================================================================

    private func upload() {

        guard let userId = auth.userId else {
            errorMessage = "You're not logged in."
            return
        }

        isUploading = true
        errorMessage = nil

        Task {

            do {

                // SupabaseManager handles:
                //
                // One:
                //     mainImage -> one image
                //
                // Both:
                //     mainImage + secondaryImage
                //     -> combined image
                //     -> one image
                //
                // Nothing is downloaded here.

                try await SupabaseManager.shared.uploadImages(
                    userId: userId,
                    mainImage: mainImage,
                    secondaryImage: secondaryImage
                )

                await MainActor.run {

                    isUploading = false

                    onUploaded()
                }

            } catch {

                print(
                    "IMAGE UPLOAD ERROR:",
                    error
                )

                await MainActor.run {

                    isUploading = false

                    errorMessage =
                        "Send failed: \(error.localizedDescription)"
                }
            }
        }
    }
}