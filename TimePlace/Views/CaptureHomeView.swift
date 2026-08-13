import SwiftUI

struct CaptureHomeView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var camera = CameraManager()
    @State private var showPreview = false

    var body: some View {
        CameraCaptureView(camera: camera) {
            showPreview = true
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let main = camera.capturedMainImage {
                PostPreviewView(
                    mainImage: main,
                    secondaryImage: camera.capturedSecondaryImage,
                    onRetake: {
                        camera.capturedMainImage = nil
                        camera.capturedSecondaryImage = nil
                        showPreview = false
                    },
                    onUploaded: {
                        camera.capturedMainImage = nil
                        camera.capturedSecondaryImage = nil
                        showPreview = false
                    }
                )
                .environmentObject(auth)
            }
        }
    }
}
