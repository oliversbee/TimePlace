import SwiftUI

struct CaptureHomeView: View {
    @EnvironmentObject var auth: AuthManager

    @StateObject private var camera = CameraManager()
    @State private var showPreview = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            cameraContent
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(auth)
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        CameraCaptureView(
            camera: camera,

            // Open Settings directly
            onOpenMenu: {
                showSettings = true
            },

            onCaptured: {
                showPreview = true
            }
        )
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