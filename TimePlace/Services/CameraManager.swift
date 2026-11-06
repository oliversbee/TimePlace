import Foundation
import AVFoundation
import UIKit
import QuartzCore
import OSLog

enum CameraError: Error {
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
    @Published private(set) var isMultiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported

    let session: AVCaptureSession
    let backPreviewLayer: AVCaptureVideoPreviewLayer
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    private(set) var backDevice: AVCaptureDevice?
    private(set) var frontDevice: AVCaptureDevice?
    private var backInput: AVCaptureDeviceInput?
    private var isUsingUltraWide = false

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
    
    private let logger = Logger(subsystem: "com.timeplace.app", category: "Camera")

    override init() {
        let multi = AVCaptureMultiCamSession.isMultiCamSupported
        let s: AVCaptureSession = multi ? AVCaptureMultiCamSession() : AVCaptureSession()
        session = s
        
        // FIX: Use standard initializer for non-multicam so it auto-connects
        backPreviewLayer = multi
            ? AVCaptureVideoPreviewLayer(sessionWithNoConnection: s)
            : AVCaptureVideoPreviewLayer(session: s)
            
        frontPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: s)
        
        super.init()
        backPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.videoGravity = .resizeAspectFill
        
        // Restore brightness if the app goes to the background during a flash
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.endFlash()
        }
    }
    
    // FIX: Remove observer to prevent memory leaks
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.errorMessage = "Camera access is off. Enable it in Settings." }
                return
            }
            self.sessionQueue.async {
                self.configureIfNeeded()
                guard self.isConfigured else { return }
                guard !self.session.isRunning else { return }
                self.session.startRunning()
                let running = self.session.isRunning
                if running { self.setZoomFactor(1.0) }
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

    private func restoreBackCameraInput(_ input: AVCaptureDeviceInput) {
        session.addInputWithNoConnections(input)
        guard let port = input.ports(for: .video, sourceDeviceType: input.device.deviceType, sourceDevicePosition: .back).first else { return }
        let outputConnection = AVCaptureConnection(inputPorts: [port], output: backOutput)
        if session.canAddConnection(outputConnection) {
            session.addConnection(outputConnection)
            applyPortraitOrientation(to: outputConnection)
        }
        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: backPreviewLayer)
        if session.canAddConnection(previewConnection) {
            session.addConnection(previewConnection)
            applyPortraitOrientation(to: previewConnection)
        }
    }

    private func setZoomFactor(_ factor: CGFloat) {
        guard mainIsBack else { return }
        let shouldUseUltraWide = factor < 1.0
        guard shouldUseUltraWide != isUsingUltraWide else { return }
        switchBackCamera(toUltraWide: shouldUseUltraWide)
    }

    func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in self?.setZoomFactor(factor) }
    }

    private func switchBackCamera(toUltraWide: Bool) {
        let deviceType: AVCaptureDevice.DeviceType = toUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
        guard let device = AVCaptureDevice.default(deviceType, for: .video, position: .back),
              let oldInput = backInput,
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }

        DispatchQueue.main.async {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.3
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.backPreviewLayer.add(transition, forKey: "cameraZoomTransition")
        }

        session.beginConfiguration()

        if isMultiCamSupported {
            if let connection = backOutput.connection(with: .video) { session.removeConnection(connection) }
            if let connection = backPreviewLayer.connection { session.removeConnection(connection) }
            session.removeInput(oldInput)

            guard session.canAddInput(newInput) else {
                restoreBackCameraInput(oldInput)
                session.commitConfiguration()
                return
            }
            session.addInputWithNoConnections(newInput)

            guard let port = newInput.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: .back).first else {
                session.removeInput(newInput)
                restoreBackCameraInput(oldInput)
                session.commitConfiguration()
                return
            }

            let outputConnection = AVCaptureConnection(inputPorts: [port], output: backOutput)
            let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: backPreviewLayer)

            guard session.canAddConnection(outputConnection), session.canAddConnection(previewConnection) else {
                session.removeInput(newInput)
                restoreBackCameraInput(oldInput)
                session.commitConfiguration()
                return
            }

            session.addConnection(outputConnection)
            session.addConnection(previewConnection)
            applyPortraitOrientation(to: outputConnection)
            applyPortraitOrientation(to: previewConnection)
        } else {
            session.removeInput(oldInput)
            guard session.canAddInput(newInput) else {
                session.addInput(oldInput)
                session.commitConfiguration()
                return
            }
            session.addInput(newInput)
            if let connection = backOutput.connection(with: .video) { applyPortraitOrientation(to: connection) }
            // FIX: Auto-created preview connection needs portrait orientation applied
            if let previewConnection = backPreviewLayer.connection { applyPortraitOrientation(to: previewConnection) }
        }

        backInput = newInput
        backDevice = device
        isUsingUltraWide = toUltraWide
        session.commitConfiguration()

        DispatchQueue.main.async { self.isTorchAvailable = device.hasTorch }
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
        session.beginConfiguration()
        do {
            if isMultiCamSupported {
                try addBackCamera()
                try addFrontCamera()
            } else {
                try addBackCameraStandard()
            }
            session.commitConfiguration()
            isConfigured = true
            
            let torchAvailable = backDevice?.hasTorch ?? false
            let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back)
            let hasUltraWideHardware = !discovery.devices.isEmpty
            
            DispatchQueue.main.async {
                self.isTorchAvailable = torchAvailable
                self.isUltraWideAvailable = hasUltraWideHardware
                self.errorMessage = nil
                if !self.isMultiCamSupported { self.captureMode = .single }
            }
        } catch {
            session.commitConfiguration()
            logger.error("Camera setup failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.errorMessage = "Camera setup failed. Try relaunching the app." }
        }
    }

    private func addBackCameraStandard() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { throw CameraError.setupFailed }
        backDevice = device
        backInput = input
        isUsingUltraWide = false
        session.addInput(input)

        guard session.canAddOutput(backOutput) else { throw CameraError.setupFailed }
        session.addOutput(backOutput)
        if let connection = backOutput.connection(with: .video) { applyPortraitOrientation(to: connection) }
        // FIX: Auto-created preview connection needs portrait orientation applied
        if let previewConnection = backPreviewLayer.connection { applyPortraitOrientation(to: previewConnection) }
    }

    private func addBackCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { throw CameraError.setupFailed }
        backDevice = device
        backInput = input
        isUsingUltraWide = false
        session.addInputWithNoConnections(input)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: .back).first else { throw CameraError.setupFailed }
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
              session.canAddInput(input) else { throw CameraError.setupFailed }
        frontDevice = device
        session.addInputWithNoConnections(input)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: .front).first else { throw CameraError.setupFailed }
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
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        } else {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        }
    }

    func swapMain() {
        guard isMultiCamSupported else { return }
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
                if self.originalBrightness == nil { self.originalBrightness = UIScreen.main.brightness }
                UIScreen.main.brightness = 1.0
                self.isScreenFlashing = true
            }
        }
        if torch { sessionQueue.async { [weak self] in self?.setTorchInternal(true) } }

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

        let mode = isMultiCamSupported ? captureMode : .single
        let useBack = isMultiCamSupported ? mainIsBack : true
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
        let mode = isMultiCamSupported ? captureMode : .single
        let useBack = isMultiCamSupported ? mainIsBack : true
        let back = backCaptureImage
        let front = frontCaptureImage
        var main: UIImage?
        var secondary: UIImage?

        switch mode {
        case .both:
            guard let back, let front else { captureLock.unlock(); return }
            main = useBack ? back : front
            secondary = useBack ? front : back
        case .single:
            guard let image = useBack ? back : front else { captureLock.unlock(); return }
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
            logger.error("Camera capture failed: \(error?.localizedDescription ?? "Unknown error")")
            
            captureLock.lock()
            isCapturing = false
            captureCompletion = nil
            captureLock.unlock()
            endFlash()
            
            DispatchQueue.main.async {
                self.errorMessage = "Failed to capture photo. Please try again."
            }
            return
        }

        captureLock.lock()
        if output === backOutput { backCaptureImage = image }
        else if output === frontOutput { frontCaptureImage = image }
        captureLock.unlock()

        finishCaptureIfReady()
    }
}