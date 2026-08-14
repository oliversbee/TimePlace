import SwiftUI

struct CaptureHomeView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var camera = CameraManager()
    @State private var showPreview = false

    /// Whether the menu is fully open.
    @State private var menuIsOpen = false

    /// The live horizontal drag while the menu is being opened/closed.
    @State private var dragTranslation: CGFloat = 0

    /// The menu occupies the left half of the screen.
    private let menuWidthFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let menuWidth = geo.size.width * menuWidthFraction

            ZStack(alignment: .leading) {

                // MENU
                // This stays underneath the camera but remains fully tappable
                // when the menu is open.
                SideMenuView {
                    Task {
                        await auth.signOut()
                    }
                }
                .frame(width: menuWidth)
                .frame(maxHeight: .infinity)
                .zIndex(0)

                // CAMERA
                cameraContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: currentOffset(menuWidth: menuWidth))
                    // IMPORTANT:
                    // When the menu is open, the camera must not intercept
                    // taps intended for the menu.
                    .allowsHitTesting(!menuIsOpen)
                    .shadow(
                        color: .black.opacity(isShifted ? 0.4 : 0),
                        radius: 16,
                        x: -4
                    )
                    .zIndex(1)

                // ONLY the visible camera area can close the menu by tapping.
                if menuIsOpen {
                    HStack(spacing: 0) {
                        Spacer()

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                setMenuOpen(false)
                            }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .zIndex(2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .ignoresSafeArea()

            // This gesture belongs to the container, not the menu button
            // or camera controls.
            .simultaneousGesture(
                dragGesture(menuWidth: menuWidth)
            )
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

    private var isShifted: Bool {
        menuIsOpen || dragTranslation != 0
    }

    private func currentOffset(menuWidth: CGFloat) -> CGFloat {
        (menuIsOpen ? menuWidth : 0) + dragTranslation
    }

    private func dragGesture(menuWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                // Only react to predominantly horizontal gestures.
                guard abs(horizontal) > abs(vertical) else {
                    return
                }

                if menuIsOpen {
                    // Menu is open: only allow movement back to the left.
                    dragTranslation = min(0, max(-menuWidth, horizontal))
                } else {
                    // Menu is closed: only allow movement to the right.
                    dragTranslation = max(0, min(menuWidth, horizontal))
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let threshold = menuWidth * 0.3

                if menuIsOpen {
                    // A left swipe closes the menu.
                    setMenuOpen(horizontal < -threshold)
                } else {
                    // A right swipe opens the menu.
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
