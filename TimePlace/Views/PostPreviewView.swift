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

                // MARK: Main Image

                Image(uiImage: mainImage)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()

                // MARK: Secondary Image

                if let secondaryImage {

                    secondaryImageView(
                        image: secondaryImage,
                        screenSize: geometry.size
                    )
                }

                // MARK: Controls

                controls
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
            }
            .background(Color.black)
            .ignoresSafeArea()
        }
    }

    // =====================================================================
    // SECONDARY IMAGE
    // =====================================================================

    private func secondaryImageView(
        image: UIImage,
        screenSize: CGSize
    ) -> some View {

        let maxWidth: CGFloat = 120
        let maxHeight: CGFloat = 160

        let isPortrait: Bool = {
            switch image.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                return true
            default:
                return false
            }
        }()

        let imageWidth = isPortrait ? image.size.height : image.size.width
        let imageHeight = isPortrait ? image.size.width : image.size.height
        let aspectRatio = imageHeight / max(imageWidth, 1)

        let width = min(maxWidth, maxHeight / max(aspectRatio, 0.001))
        let height = width * aspectRatio

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(
                width: width,
                height: height
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white, lineWidth: 3)
            )
            .shadow(radius: 6)
            // Same anchor as the live camera PiP: 20 pt from the right
            // and 140 pt from the bottom, independent of the fitted size.
            .position(
                x: screenSize.width - 20 - width / 2,
                y: screenSize.height - 140 - height / 2
            )
    }

    // =====================================================================
    // CONTROLS
    // =====================================================================

    private var controls: some View {

        VStack {

            if let errorMessage {
                GlassStatusBanner(text: errorMessage)
                    .padding(.top, 20)
            }

            Spacer()

            HStack(spacing: 16) {

                Button("Retake", action: onRetake)
                    .buttonStyle(
                        SecondaryCapsuleButtonStyle(
                            isDisabled: isUploading
                        )
                    )
                    .disabled(isUploading)

                Button {
                    upload()
                } label: {

                    Group {

                        if isUploading {

                            ProgressView()
                                .tint(.white)

                        } else {

                            Label(
                                "Send",
                                systemImage: "paperplane.fill"
                            )
                        }
                    }
                    .frame(minWidth: 40)
                }
                .buttonStyle(
                    PrimaryCapsuleButtonStyle(
                        isDisabled: isUploading
                    )
                )
                .disabled(isUploading)
            }
            .padding(.bottom, 44)
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