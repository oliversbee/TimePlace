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

        ZStack {

            // MARK: Main Image

            Image(uiImage: mainImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottomTrailing) {

            // MARK: Secondary Image

            if let secondaryImage {

                Image(uiImage: secondaryImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white, lineWidth: 3)
                    )
                    .padding(.trailing, 20)
                    .padding(.bottom, 140)
                    .shadow(radius: 6)
            }
        }
        .overlay {

            // =========================================================
            // CONTROLS
            // =========================================================
            //
            // This overlay is given the full screen frame explicitly.
            // Without that, the outer ZStack's alignment pulls the whole
            // VStack — buttons included — toward one corner instead of
            // centering it, which was the off-screen-looking bug.
            //
            controls
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .ignoresSafeArea()
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
                        SecondaryCapsuleButtonStyle(isDisabled: isUploading)
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

                            Label("Send", systemImage: "paperplane.fill")
                        }
                    }
                    .frame(minWidth: 40)
                }
                .buttonStyle(
                    PrimaryCapsuleButtonStyle(isDisabled: isUploading)
                )
                .disabled(isUploading)
            }
            .padding(.bottom, 44)
        }
    }

    // MARK: Upload

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
