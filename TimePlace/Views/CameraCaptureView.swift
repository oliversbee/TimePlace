import SwiftUI
import AVFoundation
import UIKit

struct CameraCaptureView: View {

    @ObservedObject var camera: CameraManager

    var onOpenMenu: () -> Void
    var onCaptured: () -> Void

    private let pipWidth: CGFloat = 120
    private let pipHeight: CGFloat = 160
    private let pipTrailingInset: CGFloat = 20
    private let pipBottomInset: CGFloat = 140

    @State private var isUltraWideActive: Bool = false
    
    private let shutterHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let toggleHaptic = UISelectionFeedbackGenerator()

    var body: some View {
        ZStack {
            Color.black

            GeometryReader { geo in
                let backPiPSize = pipSize(for: camera.backPreviewLayer)
                let frontPiPSize = pipSize(for: camera.frontPreviewLayer)

                ZStack {
                    CameraPreview(previewLayer: camera.backPreviewLayer)
                        .modifier(PreviewSlot(isMain: camera.mainIsBack, isVisible: camera.mainIsBack || camera.captureMode == .both, container: geo.size, pipSize: backPiPSize, pipTrailingInset: pipTrailingInset, pipBottomInset: pipBottomInset, onTapWhenPiP: { swapMainCamera() }))

                    CameraPreview(previewLayer: camera.frontPreviewLayer)
                        .modifier(PreviewSlot(isMain: !camera.mainIsBack, isVisible: !camera.mainIsBack || camera.captureMode == .both, container: geo.size, pipSize: frontPiPSize, pipTrailingInset: pipTrailingInset, pipBottomInset: pipBottomInset, onTapWhenPiP: { swapMainCamera() }))
                }
            }

            controls

            if camera.isScreenFlashing {
                Color.white.ignoresSafeArea().allowsHitTesting(false).transition(.identity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            shutterHaptic.prepare()
            toggleHaptic.prepare()
            camera.start()
            
            // Force UI state to 1x and apply hardware zoom
            isUltraWideActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                applyZoom(1.0)
            }
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.mainIsBack) { _ in
            isUltraWideActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                applyZoom(1.0)
            }
        }
    }

    private func applyZoom(_ factor: CGFloat) {
        // Use the actual device from CameraManager, not the session inputs
        guard let device = camera.mainIsBack ? camera.backDevice : camera.frontDevice else { return }
        
        do {
            try device.lockForConfiguration()
            let clamped = max(device.minAvailableVideoZoomFactor, min(device.maxAvailableVideoZoomFactor, factor))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            print("Zoom configuration error:", error)
        }
    }

    private func toggleZoom() {
        guard camera.mainIsBack, camera.isUltraWideAvailable else { return }
        
        let target: CGFloat = isUltraWideActive ? 1.0 : 0.5
        applyZoom(target)
        isUltraWideActive.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func swapMainCamera() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        camera.swapMain()
    }

    private func pipSize(for previewLayer: AVCaptureVideoPreviewLayer?) -> CGSize {
        let maximumSize = CGSize(width: pipWidth, height: pipHeight)
        guard let previewLayer, let session = previewLayer.session else { return maximumSize }

        let previewPortIDs = Set((previewLayer.connection?.inputPorts ?? []).map { ObjectIdentifier($0) })
        let photoOutputs = session.outputs.compactMap { $0 as? AVCapturePhotoOutput }

        let matchingOutput = photoOutputs.first { output in
            guard let outputConnection = output.connection(with: .video) else { return false }
            return outputConnection.inputPorts.contains { port in previewPortIDs.contains(ObjectIdentifier(port)) }
        } ?? photoOutputs.first

        guard let matchingOutput else { return maximumSize }

        if #available(iOS 16.0, *) {
            let dimensions = matchingOutput.maxPhotoDimensions
            if dimensions.width > 0, dimensions.height > 0 {
                let orientation = matchingOutput.connection(with: .video)?.videoOrientation ?? .portrait
                let isPortrait = (orientation == .portrait || orientation == .portraitUpsideDown)
                let sourceWidth = isPortrait ? CGFloat(dimensions.height) : CGFloat(dimensions.width)
                let sourceHeight = isPortrait ? CGFloat(dimensions.width) : CGFloat(dimensions.height)
                return fittedPiPSize(for: CGSize(width: sourceWidth, height: sourceHeight))
            }
        }
        return maximumSize
    }

    private func fittedPiPSize(for sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return CGSize(width: pipWidth, height: pipHeight) }
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

    private var controls: some View {
        VStack {
            ZStack(alignment: .center) {
                HStack {
                    GlassIconButton(systemName: "gearshape.fill", action: onOpenMenu)
                    Spacer()
                    GlassIconButton(systemName: flashIcon, tint: camera.flashMode == .off ? .white : .yellow, action: camera.cycleFlashMode)
                }
                
                // CUSTOM DARK NATIVE-LOOKING PILL
                HStack(spacing: 0) {
                    Button {
                        if camera.captureMode != .single {
                            camera.captureMode = .single
                            toggleHaptic.selectionChanged()
                        }
                    } label: {
                        Text("One")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(camera.captureMode == .single ? .black : .white)
                            .frame(width: 70, height: 32)
                            .background(
                                Capsule().fill(camera.captureMode == .single ? Color.white : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        if camera.captureMode != .both {
                            camera.captureMode = .both
                            toggleHaptic.selectionChanged()
                        }
                    } label: {
                        Text("Both")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(camera.captureMode == .both ? .black : .white)
                            .frame(width: 70, height: 32)
                            .background(
                                Capsule().fill(camera.captureMode == .both ? Color.white : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color(white: 0.2).opacity(0.9))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)

            if let error = camera.errorMessage {
                GlassStatusBanner(text: error).padding(.top, 12)
            }

            Spacer()

            VStack(spacing: 16) {
                zoomToggle

                ZStack(alignment: .center) {
                    HStack {
                        Spacer()
                        GlassIconButton(systemName: "arrow.triangle.2.circlepath.camera", action: swapMainCamera)
                    }
                    .padding(.horizontal, 20)

                    Button {
                        shutterHaptic.impactOccurred()
                        shutterHaptic.prepare()
                        camera.capturePhoto(completion: onCaptured)
                    } label: {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                            .overlay(Circle().fill(.white).frame(width: 64, height: 64))
                    }
                    .buttonStyle(ShutterPressStyle())
                }
            }
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var zoomToggle: some View {
        if camera.mainIsBack && camera.isUltraWideAvailable {
            Button {
                toggleZoom()
            } label: {
                Text(isUltraWideActive ? "0.5x" : "1x")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isUltraWideActive ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(isUltraWideActive ? Color.yellow : Color.white.opacity(0.2))
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}

private struct PreviewSlot: ViewModifier {
    let isMain: Bool
    let isVisible: Bool
    let container: CGSize
    let pipSize: CGSize
    let pipTrailingInset: CGFloat
    let pipBottomInset: CGFloat
    let onTapWhenPiP: () -> Void

    private var size: CGSize { isMain ? container : pipSize }

    private var center: CGPoint {
        if isMain { return CGPoint(x: container.width / 2, y: container.height / 2) }
        return CGPoint(x: container.width - pipTrailingInset - pipSize.width / 2, y: container.height - pipBottomInset - pipSize.height / 2)
    }

    private var cornerRadius: CGFloat { isMain ? 0 : 24 }

    func body(content: Content) -> some View {
        content
            .frame(width: max(size.width, 1), height: max(size.height, 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white, lineWidth: isMain ? 0 : 3.5))
            .shadow(radius: isMain ? 0 : 6)
            .position(x: center.x, y: center.y)
            .opacity(isVisible ? 1 : 0)
            .zIndex(isMain ? 0 : 1)
            .allowsHitTesting(isVisible && !isMain)
            .onTapGesture { onTapWhenPiP() }
            .transaction { $0.animation = nil }
    }
}