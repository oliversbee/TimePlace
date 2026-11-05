import Foundation
import AVFoundation
import UIKit

enum CameraError: Error {
    case unsupportedDevice
    case setupFailed
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case both = "Both"
    case single = "One"
    var id: String { rawValue }
}

enum FlashMode: String, CaseIterable, Identifiable {
    case off, on, auto
    var id: String { rawValue }
}

final class CameraManager: NSObject, ObservableObject {

    @Published var isSessionRunning = false
    @Published var errorMessage: String?
    @Published var mainIsBack = true
    @Published var captureMode: CaptureMode = .both
    @Published var flashMode: FlashMode = .off
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var isScreenFlashing = false
    @Published var capturedMainImage: UIImage?
    @Published var capturedSecondaryImage: UIImage?
    
    @Published private(set) var isUltraWideAvailable = false

    let session = AVCaptureMultiCamSession()
    let backPreviewLayer: AVCaptureVideoPreviewLayer
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    // Expose the actual virtual devices so the view can adjust zoom correctly
    private(set) var backDevice: AVCaptureDevice?
    private(set) var frontDevice: AVCaptureDevice?

    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.app.camera.session")
    private var isConfigured = false
    private var backCaptureImage: UIImage?
    private var frontCaptureImage: UIImage?
    private var captureCompletion: (() -> Void)?
    private var isCapturing = false
    private let captureLock = NSLock()

    private var originalBrightness: CGFloat?
    private var flashSafetyTimer: DispatchWorkItem?
    private let flashWarmUp: TimeInterval = 0.22
    private let flashMaxDuration: TimeInterval = 3.0

    override init() {
        backPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        frontPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        super.init()
        backPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.videoGravity = .resizeAspectFill
    }

    func start() {
        requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.errorMessage = "Camera access is off. Enable it in Settings."
                }
                return
            }
            self.sessionQueue.async {
                self.configureIfNeeded()
                guard self.isConfigured else { return }
                guard !self.session.isRunning else { return }
                self.session.startRunning()
                let running = self.session.isRunning
                DispatchQueue.main.async { self.isSessionRunning = running }
            }
        }
    }

    func stop() {
        endFlash()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: completion(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { granted in completion(granted) }
        default: completion(false)
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            DispatchQueue.main.async {
                self.errorMessage = "This device doesn't support simultaneous front and back camera capture."
            }
            return
        }

        session.beginConfiguration()
        do {
            try addBackCamera()
            try addFrontCamera()
            session.commitConfiguration()
            isConfigured = true
            
            // FIX: Force zoom back to 1.0x immediately after setup
            if let device = backDevice {
                try? device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
            }
            
            let torchAvailable = backDevice?.hasTorch ?? false
            let hasUltraWideHardware = backDevice?.minAvailableVideoZoomFactor ?? 1.0 <= 0.5 + 0.001
            
            DispatchQueue.main.async {
                self.isTorchAvailable = torchAvailable
                self.isUltraWideAvailable = hasUltraWideHardware
                self.errorMessage = nil
            }
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.errorMessage = "Camera setup failed. Try relaunching the app."
            }
        }
    }

    private func addBackCamera() throws {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualWideCamera, .builtInTripleCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            throw CameraError.setupFailed
        }

        backDevice = device
        session.addInputWithNoConnections(input)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: .back).first else {
            throw CameraError.setupFailed
        }

        guard session.canAddOutput(backOutput) else { throw CameraError.setupFailed }
        session.addOutputWithNoConnections(backOutput)

        let outputConnection = AVCaptureConnection(inputPorts: [port], output: backOutput)
        guard session.canAddConnection(outputConnection) else { throw CameraError.setupFailed }
        session.addConnection(outputConnection)
        applyPortraitOrientation(to: outputConnection)

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: backPreviewLayer)
        guard session.canAddConnection(previewConnection) else { throw CameraError.setupFailed }
        session.addConnection(previewConnection)
        applyPortraitOrientation(to: previewConnection)
    }

    private func addFrontCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            throw CameraError.setupFailed
        }

        frontDevice = device
        session.addInputWithNoConnections(input)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: .front).first else {
            throw CameraError.setupFailed
        }

        guard session.canAddOutput(frontOutput) else { throw CameraError.setupFailed }
        session.addOutputWithNoConnections(frontOutput)

        let outputConnection = AVCaptureConnection(inputPorts: [port], output: frontOutput)
        guard session.canAddConnection(outputConnection) else { throw CameraError.setupFailed }
        session.addConnection(outputConnection)
        applyPortraitOrientation(to: outputConnection)

        if outputConnection.isVideoMirroringSupported {
            outputConnection.automaticallyAdjustsVideoMirroring = false
            outputConnection.isVideoMirrored = true
        }

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: frontPreviewLayer)
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = true
        }
        guard session.canAddConnection(previewConnection) else { throw CameraError.setupFailed }
        session.addConnection(previewConnection)
        applyPortraitOrientation(to: previewConnection)
    }

    private func applyPortraitOrientation(to connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }

    func swapMain() {
        mainIsBack.toggle()
    }

    func cycleFlashMode() {
        switch flashMode {
        case .off:  flashMode = .on
        case .on:   flashMode = .auto
        case .auto: flashMode = .off
        }
    }

    private func shouldFireFlash() -> Bool {
        switch flashMode {
        case .off: return false
        case .on: return true
        case .auto:
            guard let device = backDevice else { return false }
            let maxISO = device.activeFormat.maxISO
            guard maxISO > 0 else { return false }
            return (device.iso / maxISO) > 0.55
        }
    }

    private func beginFlash(torch: Bool, screen: Bool) {
        if screen {
            DispatchQueue.main.async {
                if self.originalBrightness == nil {
                    self.originalBrightness = UIScreen.main.brightness
                }
                UIScreen.main.brightness = 1.0
                self.isScreenFlashing = true
            }
        }
        if torch {
            sessionQueue.async { [weak self] in self?.setTorchInternal(true) }
        }

        flashSafetyTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endFlash() }
        flashSafetyTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + flashMaxDuration, execute: work)
    }

    private func endFlash() {
        flashSafetyTimer?.cancel()
        flashSafetyTimer = nil
        sessionQueue.async { [weak self] in self?.setTorchInternal(false) }
        DispatchQueue.main.async {
            self.isScreenFlashing = false
            if let brightness = self.originalBrightness {
                UIScreen.main.brightness = brightness
                self.originalBrightness = nil
            }
        }
    }

    private func setTorchInternal(_ on: Bool) {
        guard let device = backDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: 1.0) } else { device.torchMode = .off }
            device.unlockForConfiguration()
        } catch { }
    }

    func capturePhoto(completion: @escaping () -> Void) {
        guard isConfigured else { return }

        captureLock.lock()
        guard !isCapturing else {
            captureLock.unlock()
            return
        }
        isCapturing = true
        backCaptureImage = nil
        frontCaptureImage = nil
        captureCompletion = completion
        captureLock.unlock()

        let mode = captureMode
        let useBack = mainIsBack
        let fire = shouldFireFlash()
        let needsTorch = fire && (mode == .both || useBack)
        let needsScreen = fire && (mode == .both || !useBack)

        if fire { beginFlash(torch: needsTorch, screen: needsScreen) }

        let delay = fire ? flashWarmUp : 0

        sessionQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            switch mode {
            case .both:
                self.backOutput.capturePhoto(with: self.makeSettings(for: self.backOutput), delegate: self)
                self.frontOutput.capturePhoto(with: self.makeSettings(for: self.frontOutput), delegate: self)
            case .single:
                let output = useBack ? self.backOutput : self.frontOutput
                output.capturePhoto(with: self.makeSettings(for: output), delegate: self)
            }
        }
    }

    private func makeSettings(for output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(.off) { settings.flashMode = .off }
        return settings
    }

    private func finishCaptureIfReady() {
        captureLock.lock()
        let mode = captureMode
        let back = backCaptureImage
        let front = frontCaptureImage
        var main: UIImage?
        var secondary: UIImage?

        switch mode {
        case .both:
            guard let back, let front else { captureLock.unlock(); return }
            main = mainIsBack ? back : front
            secondary = mainIsBack ? front : back
        case .single:
            guard let image = mainIsBack ? back : front else { captureLock.unlock(); return }
            main = image
            secondary = nil
        }

        let completion = captureCompletion
        captureCompletion = nil
        isCapturing = false
        captureLock.unlock()

        endFlash()

        DispatchQueue.main.async { [weak self] in
            self?.capturedMainImage = main
            self?.capturedSecondaryImage = secondary
            completion?()
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            captureLock.lock()
            isCapturing = false
            captureCompletion = nil
            captureLock.unlock()
            endFlash()
            return
        }

        captureLock.lock()
        if output === backOutput { backCaptureImage = image }
        else if output === frontOutput { frontCaptureImage = image }
        captureLock.unlock()

        finishCaptureIfReady()
    }
}