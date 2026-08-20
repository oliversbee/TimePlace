import SwiftUI

struct CaptureHomeView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var camera = CameraManager()
    @State private var showPreview = false
    @State private var showSettings = false
    @State private var menuIsOpen = false

    private let menuWidthFraction: CGFloat = 0.55

    var body: some View {
        GeometryReader { geo in
            let menuWidth = geo.size.width * menuWidthFraction

            ZStack(alignment: .leading) {
                // Base background for entire screen behind everything
                Color.black
                    .ignoresSafeArea()

                // Side Menu Container bounded tightly to its width
                HStack(spacing: 0) {
                    SideMenuView(
                        onOpenSettings: {
                            setMenuOpen(false)
                            showSettings = true
                        },
                        onSignOut: {
                            setMenuOpen(false)
                            Task { await auth.signOut() }
                        }
                    )
                    .frame(width: menuWidth)
                    
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Camera View
                cameraContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(closeOverlay)
                    .offset(x: menuIsOpen ? menuWidth : 0)
                    .shadow(color: menuIsOpen ? .black.opacity(0.4) : .clear, radius: 10, x: -4)
            }
            .ignoresSafeArea()
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(auth)
            }
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        CameraCaptureView(
            camera: camera,
            onOpenMenu: {
                setMenuOpen(true)
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

    @ViewBuilder
    private var closeOverlay: some View {
        if menuIsOpen {
            Color.black.opacity(0.001)
                .onTapGesture {
                    setMenuOpen(false)
                }
        }
    }

    private func setMenuOpen(_ open: Bool) {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
            menuIsOpen = open
        }
    }
}