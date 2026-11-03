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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    
                    // Top spacer to balance the layout and clear the status bar
                    Spacer(minLength: max(geometry.safeAreaInsets.top, 20))
                    
                    // Error Banner
                    if let errorMessage {
                        GlassStatusBanner(text: errorMessage)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }

                    // =========================================================
                    // IMAGE PREVIEW AREA
                    // =========================================================
                    ZStack(alignment: .bottomTrailing) {
                        
                        // Main Image
                        Image(uiImage: mainImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                        
                        // Secondary PiP Image
                        if let secondaryImage {
                            secondaryImageView(image: secondaryImage)
                        }
                    }
                    // Constrain the image to a 3:4 portrait aspect ratio so it acts like a card
                    .aspectRatio(3/4, contentMode: .fit)
                    .padding(.horizontal, 24)
                    
                    // Spacer between image and buttons
                    Spacer(minLength: 24)
                    
                    // =========================================================
                    // BOTTOM CONTROLS
                    // =========================================================
                    controls
                        .padding(.horizontal, 24)
                    
                    // Bottom spacer to balance the layout
                    Spacer(minLength: max(geometry.safeAreaInsets.bottom, 20))
                }
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
            .scaledToFill() // Fill the frame to avoid letterboxing
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white, lineWidth: 3.5)
            )
            .padding(20) // Keeps the PiP inset from the edges of the main image card
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
                .clipShape(Capsule())
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
                .clipShape(Capsule())
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