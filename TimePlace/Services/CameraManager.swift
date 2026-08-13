import Foundation
import AVFoundation
import UIKit

enum CameraError: Error {
    case unsupportedDevice
    case setupFailed
}

/// Whether a capture should save both the front and back photos, or just
/// whichever camera is currently set as "main".
enum CaptureMode: String, CaseIterable, Identifiable {
    case both = "Both"
    case single = "One"

    var id: String { rawValue }
}

/// Runs the front and back cameras simultaneously via AVCaptureMultiCamSession
/// (BeReal-style dual capture). Requires a physical device — iPhone XS/XR or
/// newer — the simulator does not support multi-cam sessions.
final class CameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var errorMessage: String?

    /// Which physical camera is currently shown large/full-screen.
    /// The other camera is shown small, in the bottom-right corner
    /// (only relevant when captureMode == .both).
    @Published var mainIsBack = true

    /// Whether a capture should keep both photos or just the "main" one.
    @Published var captureMode: CaptureMode = .both

    @Published var capturedMainImage: UIImage?
    @Published var capturedSecondaryImage: UIImage?

    let session = AVCaptureMultiCamSession()

    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()

    private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    private var backCaptureImage: UIImage?
    private var frontCaptureImage: UIImage?
    private var captureCompletion: (() -> Void)?

    func configure() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            errorMessage = "This device doesn't support simultaneous front and back camera capture."
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        do {
            try addBackCamera()
            try addFrontCamera()
        } catch {
            errorMessage = "Camera setup failed. Try relaunching the app."
        }
    }

    private func addBackCamera() throws {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { throw CameraError.setupFailed }
        session.addInputWithNoConnections(input)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: .back).first else {
            throw CameraError.setupFailed
        }

        guard session.canAddOutput(backOutput) else { throw CameraError.setupFailed }
        session.addOutputWithNoConnections(backOutput)

        let outputConnection = AVCaptureConnection(inputPorts: [port], output: backOutput)
        guard session.canAddConnection(outputConnection) else { throw CameraError.setupFailed }
        session.addConnection(outputConnection)
        if outputConnection.isVideoOrientationSupported {
            outputConnection.videoOrientation = .portrait
        }

        let previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        previewLayer.videoGravity = .resizeAspectFill
        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else { throw CameraError.setupFailed }
        session.addConnection(previewConnection)
        backPreviewLayer = previewLayer
    }

    private func addFrontCamera() throws {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { throw CameraError.setupFailed }
        session.addInputWithNoConnections(input)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: .front).first else {
            throw CameraError.setupFailed
        }

        guard session.canAddOutput(frontOutput) else { throw CameraError.setupFailed }
        session.addOutputWithNoConnections(frontOutput)

        let outputConnection = AVCaptureConnection(inputPorts: [port], output: frontOutput)
        guard session.canAddConnection(outputConnection) else { throw CameraError.setupFailed }
        session.addConnection(outputConnection)
        if outputConnection.isVideoOrientationSupported {
            outputConnection.videoOrientation = .portrait
        }
        outputConnection.isVideoMirrored = true

        let previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        previewLayer.videoGravity = .resizeAspectFill
        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        previewConnection.isVideoMirrored = true
        guard session.canAddConnection(previewConnection) else { throw CameraError.setupFailed }
        session.addConnection(previewConnection)
        frontPreviewLayer = previewLayer
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isSessionRunning = self.session.isRunning }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    /// In "Both" mode, swaps which camera is displayed large vs. as the small
    /// corner overlay (both are captured together either way). In "One" mode,
    /// this is effectively a camera flip, since it determines which single
    /// camera gets captured.
    func swapMain() {
        mainIsBack.toggle()
    }

    func capturePhoto(completion: @escaping () -> Void) {
        backCaptureImage = nil
        frontCaptureImage = nil
        captureCompletion = completion

        switch captureMode {
        case .both:
            backOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            frontOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        case .single:
            // Only fire the camera that's currently set as "main".
            if mainIsBack {
                backOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            } else {
                frontOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func finishCaptureIfReady() {
        switch captureMode {
        case .both:
            guard let back = backCaptureImage, let front = frontCaptureImage else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.mainIsBack {
                    self.capturedMainImage = back
                    self.capturedSecondaryImage = front
                } else {
                    self.capturedMainImage = front
                    self.capturedSecondaryImage = back
                }
                self.captureCompletion?()
                self.captureCompletion = nil
            }
        case .single:
            let image = mainIsBack ? backCaptureImage : frontCaptureImage
            guard let image else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.capturedMainImage = image
                self.capturedSecondaryImage = nil
                self.captureCompletion?()
                self.captureCompletion = nil
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        if output === backOutput {
            backCaptureImage = image
        } else if output === frontOutput {
            frontCaptureImage = image
        }
        finishCaptureIfReady()
    }
}
