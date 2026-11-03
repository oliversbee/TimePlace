import SwiftUI
import AVFoundation

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

                // Match each live PiP to the corresponding camera's still-photo
                // aspect ratio. The post-capture preview uses the captured
                // UIImage's dimensions with the same 120 x 160 maximum bounds.
                let backPiPSize = pipSize(for: camera.backPreviewLayer)
                let frontPiPSize = pipSize(for: camera.frontPreviewLayer)

                ZStack {

                    // =================================================
                    // BACK CAMERA
                    // =================================================
                    CameraPreview(
                        previewLayer: camera.backPreviewLayer
                    )
                    .modifier(
                        PreviewSlot(
                            isMain: camera.mainIsBack,
                            isVisible: camera.mainIsBack
                                || camera.captureMode == .both,
                            container: geo.size,
                            pipSize: backPiPSize,
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
                            pipSize: frontPiPSize,
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

    /// Returns the PiP size that fits the camera's still-photo aspect ratio
    /// inside the same 120 x 160 point bounds used after capture.
    private func pipSize(for previewLayer: AVCaptureVideoPreviewLayer?) -> CGSize {

        let maximumSize = CGSize(width: pipWidth, height: pipHeight)

        guard
            let previewLayer,
            let session = previewLayer.session
        else {
            return maximumSize
        }

        let previewPortIDs = Set(
            (previewLayer.connection?.inputPorts ?? []).map { ObjectIdentifier($0) }
        )

        let photoOutputs = session.outputs.compactMap { $0 as? AVCapturePhotoOutput }

        let matchingOutput = photoOutputs.first { output in
            guard let outputConnection = output.connection(with: .video) else {
                return false
            }

            return outputConnection.inputPorts.contains { port in
                previewPortIDs.contains(ObjectIdentifier(port))
            }
        } ?? photoOutputs.first

        guard let matchingOutput else {
            return maximumSize
        }

        if #available(iOS 16.0, *) {
            let dimensions = matchingOutput.maxPhotoDimensions

            if dimensions.width > 0, dimensions.height > 0 {
                let orientation = matchingOutput.connection(with: .video)?.videoOrientation ?? .portrait
                let isPortrait = (orientation == .portrait || orientation == .portraitUpsideDown)
                let sourceWidth = isPortrait ? CGFloat(dimensions.height) : CGFloat(dimensions.width)
                let sourceHeight = isPortrait ? CGFloat(dimensions.width) : CGFloat(dimensions.height)

                return fittedPiPSize(
                    for: CGSize(
                        width: sourceWidth,
                        height: sourceHeight
                    )
                )
            }
        }

        return maximumSize
    }

    private func fittedPiPSize(for sourceSize: CGSize) -> CGSize {

        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: pipWidth, height: pipHeight)
        }

        let aspectRatio = sourceSize.height / sourceSize.width
        let width = min(pipWidth, pipHeight / aspectRatio)
        let height = width * aspectRatio

        return CGSize(width: width, height: height)
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
            ZStack(alignment: .center) {
                
                HStack {
                    GlassIconButton(
                        systemName: "gearshape.fill",
                        action: onOpenMenu
                    )
                    
                    Spacer()
                    
                    GlassIconButton(
                        systemName: flashIcon,
                        tint: camera.flashMode == .off ? .white : .yellow,
                        action: camera.cycleFlashMode
                    )
                }
                
                CaptureModeToggle(mode: $camera.captureMode)
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
            ZStack(alignment: .center) {
                
                HStack {
                    Spacer()
                    
                    GlassIconButton(
                        systemName: "arrow.triangle.2.circlepath.camera",
                        action: camera.swapMain
                    )
                }
                .padding(.horizontal, 20)
                
                Button {
                    camera.capturePhoto(completion: onCaptured)
                } label: {

                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                        .overlay(
                            Circle()
                                .fill(Color(red: 0.94, green: 0.41, blue: 0.33)) // Coral color matching the image
                                .frame(width: 64, height: 64)
                        )
                }
                .buttonStyle(ShutterPressStyle())
            }
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
        // Unified corner radius to match the UI
        isMain ? 0 : 24
    }

    func body(content: Content) -> some View {
        content
            .frame(
                width: max(size.width, 1),
                height: max(size.height, 1)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        .white,
                        lineWidth: isMain ? 0 : 3.5
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

// =========================================================================
// CAPTURE MODE TOGGLE (Updated Corner Radius)
// =========================================================================
struct CaptureModeToggle: View {
    @Binding var mode: CameraManager.CaptureMode
    
    // Matching the 24 corner radius from PostPreviewView
    private let cornerRadius: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            // One Mode Button
            toggleButton(title: "One", icon: "square", isSelected: mode == .one) {
                mode = .one
            }
            
            // Both Mode Button
            toggleButton(title: "Both", icon: "square.split.2x1", isSelected: mode == .both) {
                mode = .both
            }
        }
        .padding(4)
        // Dark background mimicking the glass pill in the UI
        .background(Color(white: 0.15).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func toggleButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Selected state background pill matching the corner radius
            .background(isSelected ? Color.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}