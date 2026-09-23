import SwiftUI

struct CameraCaptureView: View {

    @ObservedObject var camera: CameraManager

    var onOpenMenu: () -> Void
    var onCaptured: () -> Void

    // Corner preview geometry
    private let pipWidth: CGFloat = 120
    private let pipHeight: CGFloat = 160
    private let pipTrailingInset: CGFloat = 20
    private let pipBottomInset: CGFloat = 140

    var body: some View {

        ZStack {

            Color.black

            GeometryReader { geo in

                ZStack {

                    // =================================================
                    // BACK CAMERA
                    // =================================================
                    //
                    // There is exactly ONE view per preview layer, and
                    // it never gives its layer up. Swapping main/PiP
                    // only changes the frame and position below, so a
                    // preview can never be orphaned and go black.
                    //
                    CameraPreview(
                        previewLayer: camera.backPreviewLayer
                    )
                    .modifier(
                        PreviewSlot(
                            isMain: camera.mainIsBack,
                            isVisible: camera.mainIsBack
                                || camera.captureMode == .both,
                            container: geo.size,
                            pipSize: CGSize(
                                width: pipWidth,
                                height: pipHeight
                            ),
                            pipTrailingInset: pipTrailingInset,
                            pipBottomInset: pipBottomInset,
                            onTapWhenPiP: {
                                camera.swapMain()
                            }
                        )
                    )

                    // =================================================
                    // FRONT CAMERA
                    // =================================================

                    CameraPreview(
                        previewLayer: camera.frontPreviewLayer
                    )
                    .modifier(
                        PreviewSlot(
                            isMain: !camera.mainIsBack,
                            isVisible: !camera.mainIsBack
                                || camera.captureMode == .both,
                            container: geo.size,
                            pipSize: CGSize(
                                width: pipWidth,
                                height: pipHeight
                            ),
                            pipTrailingInset: pipTrailingInset,
                            pipBottomInset: pipBottomInset,
                            onTapWhenPiP: {
                                camera.swapMain()
                            }
                        )
                    )
                }
            }

            controls

            // =========================================================
            // SCREEN FLASH
            // =========================================================
            //
            // The front camera has no lamp, so the screen becomes one.
            // Sits above everything, including the controls, and is
            // never animated — it has to be at full white immediately.
            //
            if camera.isScreenFlashing {

                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var flashIcon: String {

        switch camera.flashMode {
        case .off:  return "bolt.slash.fill"
        case .on:   return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        }
    }

    // =====================================================================
    // CONTROLS
    // =====================================================================

    private var controls: some View {

        VStack {

            // =========================================================
            // TOP BAR
            // =========================================================
            //
            // Settings stays put. Flash moves up here — where the
            // camera-flip button used to be — next to the mode toggle.
            //
            HStack(alignment: .center) {

                GlassIconButton(
                    systemName: "gearshape.fill",
                    action: onOpenMenu
                )

                Spacer()

                HStack(spacing: 10) {

                    CaptureModeToggle(mode: $camera.captureMode)

                    GlassIconButton(
                        systemName: flashIcon,
                        tint: camera.flashMode == .off ? .white : .yellow,
                        action: camera.cycleFlashMode
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)

            if let error = camera.errorMessage {

                GlassStatusBanner(text: error)
                    .padding(.top, 12)
            }

            Spacer()

            // =========================================================
            // BOTTOM BAR
            // =========================================================
            //
            // Camera-flip takes flash's old spot, right of the shutter.
            // The left spacer keeps the shutter visually centered.
            //
            HStack {

                Spacer()
                    .frame(width: 44)

                Spacer()

                Button {
                    camera.capturePhoto(completion: onCaptured)
                } label: {

                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                        .overlay(
                            Circle()
                                .fill(.white)
                                .frame(width: 64, height: 64)
                        )
                }
                .buttonStyle(ShutterPressStyle())

                Spacer()

                GlassIconButton(
                    systemName: "arrow.triangle.2.circlepath.camera",
                    action: camera.swapMain
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

private struct ShutterPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {

        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}

// =========================================================================
// PREVIEW SLOT
// =========================================================================
//
// One modifier, applied unconditionally, whose VALUES change. This is
// deliberate: an `if isMain { ... } else { ... }` around the preview would
// give SwiftUI two different view identities, tear the UIView down and
// rebuild it, and put you right back in black-preview territory.
//
private struct PreviewSlot: ViewModifier {

    let isMain: Bool
    let isVisible: Bool
    let container: CGSize
    let pipSize: CGSize
    let pipTrailingInset: CGFloat
    let pipBottomInset: CGFloat
    let onTapWhenPiP: () -> Void

    private var size: CGSize {
        isMain ? container : pipSize
    }

    private var center: CGPoint {

        if isMain {
            return CGPoint(
                x: container.width / 2,
                y: container.height / 2
            )
        }

        return CGPoint(
            x: container.width - pipTrailingInset - pipSize.width / 2,
            y: container.height - pipBottomInset - pipSize.height / 2
        )
    }

    private var cornerRadius: CGFloat {
        isMain ? 0 : 16
    }

    func body(content: Content) -> some View {

        content
            .frame(
                width: max(size.width, 1),
                height: max(size.height, 1)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        .white,
                        lineWidth: isMain ? 0 : 3
                    )
            )
            .shadow(radius: isMain ? 0 : 6)
            .position(x: center.x, y: center.y)
            .opacity(isVisible ? 1 : 0)
            .zIndex(isMain ? 0 : 1)
            .allowsHitTesting(isVisible && !isMain)
            .onTapGesture {
                onTapWhenPiP()
            }
            .transaction { $0.animation = nil }
    }
}
