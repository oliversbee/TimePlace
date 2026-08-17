import SwiftUI

struct CaptureHomeView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var camera = CameraManager()
    @State private var showPreview = false
    @State private var showSettings = false

    /// Whether the menu is pinned open (camera slid all the way to the right).
    @State private var menuIsOpen = false
    /// Live finger position while dragging, on top of whatever menuIsOpen already is.
    @State private var dragTranslation: CGFloat = 0

    /// The menu takes up the left half of the screen.
    private let menuWidthFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let menuWidth = geo.size.width * menuWidthFraction

            ZStack(alignment: .leading) {
                SideMenuView(
                    onOpenSettings: { showSettings = true },
                    onSignOut: { Task { await auth.signOut() } }
                )
                .frame(width: menuWidth)
                .frame(maxHeight: .infinity)

                cameraContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(closeOverlay) // Moved BEFORE .offset so it slides with cameraContent
                    .offset(x: currentOffset(menuWidth: menuWidth))
                    .shadow(color: .black.opacity(isShifted ? 0.4 : 0), radius: 16, x: -4)
                    .simultaneousGesture(dragGesture(menuWidth: menuWidth))
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(auth)
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
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

    /// Invisible tap-catcher shown only while the menu is open, so a tap
    /// anywhere on the (now partially visible) camera closes the menu
    /// instead of e.g. firing the shutter.
    @ViewBuilder
    private var closeOverlay: some View {
        if menuIsOpen {
            Color.black.opacity(0.001)
                .onTapGesture {
                    setMenuOpen(false)
                }
        }
    }

    private var isShifted: Bool {
        menuIsOpen || dragTranslation > 0
    }

    private func currentOffset(menuWidth: CGFloat) -> CGFloat {
        (menuIsOpen ? menuWidth : 0) + dragTranslation
    }

    private func dragGesture(menuWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // Ignore mostly-vertical drags so they don't fight other gestures.
                guard abs(horizontal) > abs(vertical) else { return }

                if menuIsOpen {
                    // Only allow dragging back left, toward closed.
                    dragTranslation = min(0, max(-menuWidth, horizontal))
                } else {
                    // Only allow dragging right, toward open.
                    dragTranslation = max(0, min(menuWidth, horizontal))
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let threshold = menuWidth * 0.3

                if menuIsOpen {
                    setMenuOpen(horizontal > -threshold)
                } else {
                    setMenuOpen(horizontal > threshold)
                }
                dragTranslation = 0
            }
    }

    private func setMenuOpen(_ open: Bool) {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
            menuIsOpen = open
        }
    }
}
