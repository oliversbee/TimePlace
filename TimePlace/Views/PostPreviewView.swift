import SwiftUI

struct PostPreviewView: View {
    @EnvironmentObject var auth: AuthManager

    let mainImage: UIImage
    /// nil when the user chose "One" camera at capture time.
    let secondaryImage: UIImage?
    var onRetake: () -> Void
    var onUploaded: () -> Void

    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: mainImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            if let secondaryImage {
                Image(uiImage: secondaryImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 3))
                    .padding(.trailing, 20)
                    .padding(.bottom, 140)
                    .shadow(radius: 6)
            }

            VStack {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .font(.footnote)
                        .padding()
                        .background(.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding()
                }

                Spacer()

                HStack(spacing: 40) {
                    Button("Retake", action: onRetake)
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .disabled(isUploading)

                    Button {
                        upload()
                    } label: {
                        Group {
                            if isUploading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Upload").fontWeight(.semibold)
                            }
                        }
                        .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUploading)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.black)
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
                isUploading = false
                onUploaded()
            } catch {
                errorMessage = "Upload failed. Check your connection and try again."
                isUploading = false
            }
        }
    }
}
