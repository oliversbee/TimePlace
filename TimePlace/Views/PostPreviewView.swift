import SwiftUI

struct PostPreviewView: View {
    @EnvironmentObject var auth: AuthManager

    let mainImage: UIImage
    let secondaryImage: UIImage?

    var onRetake: () -> Void
    var onUploaded: () -> Void

    @State private var isUploading = false
    @State private var errorMessage: String?
    
    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    private let uniformCornerRadius: CGFloat = 24

    // Adaptive Cream Colors
    private var creamBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1.0) // Dark warm gray
                : UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1.0) // Cream
        })
    }
    
    private var retakeButtonBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1.0)
                : UIColor(red: 0.92, green: 0.89, blue: 0.84, alpha: 1.0)
        })
    }

    var body: some View {
        ZStack {
            // Custom Cream Background
            creamBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                
                if let errorMessage {
                    GlassStatusBanner(text: errorMessage)
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                }

                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: mainImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous))
                    
                    if let secondaryImage {
                        secondaryImageView(image: secondaryImage)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 40)
                
                Spacer(minLength: 20)
                
                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
    }

    private func secondaryImageView(image: UIImage) -> some View {
        let maxWidth: CGFloat = 120
        let maxHeight: CGFloat = 160
        let aspectRatio = image.size.height / max(image.size.width, 1)
        let width = min(maxWidth, maxHeight / max(aspectRatio, 0.001))
        let height = width * aspectRatio

        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous)
                    .stroke(.white, lineWidth: 3.5)
            )
            .padding(20)
    }

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
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(retakeButtonBackground)
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
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: uniformCornerRadius, style: .continuous))
            }
            .disabled(isUploading)
            .opacity(isUploading ? 0.8 : 1.0)
        }
    }

    private func upload() {
        guard let userId = auth.userId else {
            errorMessage = "You're not logged in."
            return
        }

        isUploading = true
        errorMessage = nil

        Task {
            do {
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
                print("IMAGE UPLOAD ERROR:", error)
                await MainActor.run {
                    isUploading = false
                    errorMessage = "Send failed: \(error.localizedDescription)"
                }
            }
        }
    }
}