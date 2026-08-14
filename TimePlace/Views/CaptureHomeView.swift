import SwiftUI

struct CaptureHomeView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var camera = CameraManager()
    @State private var showPreview = false

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
                // The menu remains interactive while it is open.
                SideMenuView {
                    // Signing out is independent of menu dismissal.
                    Task {
                        await auth.signOut()
                    }
                }
                .frame(width: menuWidth)
                .frame(maxHeight: .infinity)
                .zIndex(0)

                cameraContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: currentOffset(menuWidth: menuWidth))
                    .shadow(
                        color: .black.opacity(isShifted ? 0.4 : 0),
                        radius: 16,
                        x: -4
                    )
                    .overlay(closeOverlay)
                    .zIndex(1)
            }
            .ignoresSafeArea()
            // Swipe handling is on the container so a left swipe can close
            // the menu without making the menu itself dismiss on a tap.
            .simultaneousGesture(dragGesture(menuWidth: menuWidth))
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

    /// Only the visible camera portion can dismiss the menu by tapping.
    /// The menu itself is not covered by this overlay.
    @ViewBuilder
    private var closeOverlay: some View {
        if menuIsOpen {
            HStack(spacing: 0) {
                Spacer()

                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        setMenuOpen(false)
                    }
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

                guard abs(horizontal) > abs(vertical) else { return }

                if menuIsOpen {
                    // Only allow dragging left, toward the camera.
                    dragTranslation = min(0, max(-menuWidth, horizontal))
                } else {
                    // Only allow dragging right, to reveal the menu.
                    dragTranslation = max(0, min(menuWidth, horizontal))
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let threshold = menuWidth * 0.3

                if menuIsOpen {
                    // Left swipe beyond the threshold closes the menu.
                    setMenuOpen(horizontal <= -threshold)
                } else {
                    // Right swipe beyond the threshold opens the menu.
                    setMenuOpen(horizontal >= threshold)
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
