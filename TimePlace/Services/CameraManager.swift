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

    var id: String {
        rawValue
    }
}

enum FlashMode: String, CaseIterable, Identifiable {
    case off
    case on
    case auto

    var id: String {
        rawValue
    }
}

final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var isSessionRunning = false
    @Published var errorMessage: String?

    @Published var mainIsBack = true
    @Published var captureMode: CaptureMode = .both

    @Published var flashMode: FlashMode = .off
    @Published private(set) var isTorchAvailable = false

    /// True only for the few hundred milliseconds around a front-camera
    /// capture. The view paints the whole screen white while this is set.
    @Published private(set) var isScreenFlashing = false

    @Published var capturedMainImage: UIImage?
    @Published var capturedSecondaryImage: UIImage?

    // MARK: - Session

    let session = AVCaptureMultiCamSession()

    // -----------------------------------------------------------------
    // IMPORTANT
    //
    // These two layers are created once, here, and each one is attached
    // to exactly ONE UIView for the entire life of the camera screen.
    //
    // A CALayer can only have a single superlayer. If the same preview
    // layer is passed to two SwiftUI views, the second view steals it
    // from the first and the first goes permanently black.
    //
    // Swapping "main" therefore must never move a layer between views.
    // The view layer only changes each preview's FRAME.
    // -----------------------------------------------------------------

    let backPreviewLayer: AVCaptureVideoPreviewLayer
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()

    private let sessionQueue = DispatchQueue(
        label: "com.app.camera.session"
    )

    private var backDevice: AVCaptureDevice?

    private var isConfigured = false

    private var backCaptureImage: UIImage?
    private var frontCaptureImage: UIImage?
    private var captureCompletion: (() -> Void)?

    private var isCapturing = false

    private let captureLock = NSLock()

    // Flash bookkeeping
    private var originalBrightness: CGFloat?
    private var flashSafetyTimer: DispatchWorkItem?

    /// How long the flash burns before the shutter fires. Auto-exposure
    /// and auto-white-balance need a moment to react to the new light,
    /// otherwise the shot comes out as if the flash never happened.
    private let flashWarmUp: TimeInterval = 0.22

    /// Hard ceiling. If a capture silently fails we must never leave the
    /// torch burning or the screen stuck white.
    private let flashMaxDuration: TimeInterval = 3.0

    // MARK: - Init

    override init() {

        // Creating a preview layer with no connection is cheap and can
        // be done before the session is configured. Doing it here means
        // the SwiftUI views always have a real layer to attach at
        // makeUIView time, so there is no "nil now, real later" gap.

        backPreviewLayer = AVCaptureVideoPreviewLayer(
            sessionWithNoConnection: session
        )

        frontPreviewLayer = AVCaptureVideoPreviewLayer(
            sessionWithNoConnection: session
        )

        super.init()

        backPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.videoGravity = .resizeAspectFill
    }

    // MARK: - Lifecycle

    /// Ask for permission, configure the session and start it.
    /// Safe to call from `onAppear` every time the view appears.
    func start() {

        requestAccess { [weak self] granted in

            guard let self else {
                return
            }

            guard granted else {

                DispatchQueue.main.async {
                    self.errorMessage =
                        "Camera access is off. Enable it in Settings."
                }

                return
            }

            self.sessionQueue.async {

                self.configureIfNeeded()

                guard self.isConfigured else {
                    return
                }

                guard !self.session.isRunning else {
                    return
                }

                self.session.startRunning()

                let running = self.session.isRunning

                DispatchQueue.main.async {
                    self.isSessionRunning = running
                }
            }
        }
    }

    func stop() {

        endFlash()

        sessionQueue.async { [weak self] in

            guard let self else {
                return
            }

            guard self.session.isRunning else {
                return
            }

            self.session.stopRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    private func requestAccess(
        completion: @escaping (Bool) -> Void
    ) {

        switch AVCaptureDevice.authorizationStatus(for: .video) {

        case .authorized:
            completion(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }

        default:
            completion(false)
        }
    }

    // MARK: - Configuration

    /// Must be called on `sessionQueue`.
    private func configureIfNeeded() {

        guard !isConfigured else {
            return
        }

        guard AVCaptureMultiCamSession.isMultiCamSupported else {

            DispatchQueue.main.async {
                self.errorMessage =
                    "This device doesn't support simultaneous front and back camera capture."
            }

            return
        }

        session.beginConfiguration()

        do {

            try addBackCamera()
            try addFrontCamera()

            session.commitConfiguration()

            isConfigured = true

            let torchAvailable = backDevice?.hasTorch ?? false

            DispatchQueue.main.async {
                self.isTorchAvailable = torchAvailable
                self.errorMessage = nil
            }

        } catch {

            session.commitConfiguration()

            DispatchQueue.main.async {
                self.errorMessage =
                    "Camera setup failed. Try relaunching the app."
            }
        }
    }

    private func addBackCamera() throws {

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CameraError.setupFailed
        }

        backDevice = device

        session.addInputWithNoConnections(input)

        guard
            let port = input.ports(
                for: .video,
                sourceDeviceType: device.deviceType,
                sourceDevicePosition: .back
            ).first
        else {
            throw CameraError.setupFailed
        }

        // -------------------------------------------------------------
        // Photo output
        // -------------------------------------------------------------

        guard session.canAddOutput(backOutput) else {
            throw CameraError.setupFailed
        }

        session.addOutputWithNoConnections(backOutput)

        let outputConnection = AVCaptureConnection(
            inputPorts: [port],
            output: backOutput
        )

        guard session.canAddConnection(outputConnection) else {
            throw CameraError.setupFailed
        }

        session.addConnection(outputConnection)

        applyPortraitOrientation(to: outputConnection)

        // -------------------------------------------------------------
        // Preview (layer already exists — only the connection is new)
        // -------------------------------------------------------------

        let previewConnection = AVCaptureConnection(
            inputPort: port,
            videoPreviewLayer: backPreviewLayer
        )

        guard session.canAddConnection(previewConnection) else {
            throw CameraError.setupFailed
        }

        session.addConnection(previewConnection)

        applyPortraitOrientation(to: previewConnection)
    }

    private func addFrontCamera() throws {

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CameraError.setupFailed
        }

        session.addInputWithNoConnections(input)

        guard
            let port = input.ports(
                for: .video,
                sourceDeviceType: device.deviceType,
                sourceDevicePosition: .front
            ).first
        else {
            throw CameraError.setupFailed
        }

        // -------------------------------------------------------------
        // Photo output
        // -------------------------------------------------------------

        guard session.canAddOutput(frontOutput) else {
            throw CameraError.setupFailed
        }

        session.addOutputWithNoConnections(frontOutput)

        let outputConnection = AVCaptureConnection(
            inputPorts: [port],
            output: frontOutput
        )

        guard session.canAddConnection(outputConnection) else {
            throw CameraError.setupFailed
        }

        session.addConnection(outputConnection)

        applyPortraitOrientation(to: outputConnection)

        if outputConnection.isVideoMirroringSupported {
            outputConnection.automaticallyAdjustsVideoMirroring = false
            outputConnection.isVideoMirrored = true
        }

        // -------------------------------------------------------------
        // Preview
        // -------------------------------------------------------------

        let previewConnection = AVCaptureConnection(
            inputPort: port,
            videoPreviewLayer: frontPreviewLayer
        )

        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = true
        }

        guard session.canAddConnection(previewConnection) else {
            throw CameraError.setupFailed
        }

        session.addConnection(previewConnection)

        applyPortraitOrientation(to: previewConnection)
    }

    private func applyPortraitOrientation(
        to connection: AVCaptureConnection
    ) {

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

    // MARK: - Camera switching

    func swapMain() {

        // Only flips which preview is drawn large. No session change,
        // no layer re-parenting, so neither preview can go black.

        mainIsBack.toggle()
    }

    // MARK: - Flash

    // -----------------------------------------------------------------
    // AVCaptureMultiCamSession does NOT support the hardware flash. The
    // photo output advertises no flash modes while multi-cam is running,
    // so `settings.flashMode = .on` does nothing.
    //
    // A normal-camera flash is reproduced by hand:
    //
    //   back  -> torch pulsed on, warm-up delay, shutter, torch off
    //   front -> screen blasted white at full brightness for the same
    //            window, exactly as the stock Camera app does
    //
    // Both are torn down as soon as the photo arrives, so nothing stays
    // lit between shots.
    // -----------------------------------------------------------------

    func cycleFlashMode() {

        switch flashMode {
        case .off:  flashMode = .on
        case .on:   flashMode = .auto
        case .auto: flashMode = .off
        }
    }

    /// Decides whether this particular shot fires.
    private func shouldFireFlash() -> Bool {

        switch flashMode {

        case .off:
            return false

        case .on:
            return true

        case .auto:

            // There's no `isFlashScene` to lean on in a multi-cam
            // session, so read the scene off the back device's own
            // exposure: a sensor pushed near the top of its ISO range
            // is in the dark, whatever the subject is.

            guard let device = backDevice else {
                return false
            }

            let maxISO = device.activeFormat.maxISO

            guard maxISO > 0 else {
                return false
            }

            return (device.iso / maxISO) > 0.55
        }
    }

    private func beginFlash(
        torch: Bool,
        screen: Bool
    ) {

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
            sessionQueue.async { [weak self] in
                self?.setTorchInternal(true)
            }
        }

        // Safety net: nothing may stay lit if the capture never lands.

        flashSafetyTimer?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.endFlash()
        }

        flashSafetyTimer = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + flashMaxDuration,
            execute: work
        )
    }

    private func endFlash() {

        flashSafetyTimer?.cancel()
        flashSafetyTimer = nil

        sessionQueue.async { [weak self] in
            self?.setTorchInternal(false)
        }

        DispatchQueue.main.async {

            self.isScreenFlashing = false

            if let brightness = self.originalBrightness {
                UIScreen.main.brightness = brightness
                self.originalBrightness = nil
            }
        }
    }

    /// Must be called on `sessionQueue`.
    private func setTorchInternal(_ on: Bool) {

        guard
            let device = backDevice,
            device.hasTorch,
            device.isTorchAvailable
        else {
            return
        }

        do {

            try device.lockForConfiguration()

            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }

            device.unlockForConfiguration()

        } catch {
            // A torch that won't light isn't worth an error banner
            // mid-capture; the photo still gets taken.
        }
    }

    // MARK: - Capture

    func capturePhoto(
        completion: @escaping () -> Void
    ) {

        guard isConfigured else {
            return
        }

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

        // Which lamp a shot needs depends on which cameras are firing.
        let needsTorch = fire && (mode == .both || useBack)
        let needsScreen = fire && (mode == .both || !useBack)

        if fire {
            beginFlash(torch: needsTorch, screen: needsScreen)
        }

        let delay = fire ? flashWarmUp : 0

        sessionQueue.asyncAfter(deadline: .now() + delay) { [weak self] in

            guard let self else {
                return
            }

            switch mode {

            case .both:

                self.backOutput.capturePhoto(
                    with: self.makeSettings(for: self.backOutput),
                    delegate: self
                )

                self.frontOutput.capturePhoto(
                    with: self.makeSettings(for: self.frontOutput),
                    delegate: self
                )

            case .single:

                let output = useBack ? self.backOutput : self.frontOutput

                output.capturePhoto(
                    with: self.makeSettings(for: output),
                    delegate: self
                )
            }
        }
    }

    private func makeSettings(
        for output: AVCapturePhotoOutput
    ) -> AVCapturePhotoSettings {

        let settings = AVCapturePhotoSettings()

        // Flash is unsupported in multi-cam sessions. Asking for it
        // raises an exception on some devices, so be explicit.
        if output.supportedFlashModes.contains(.off) {
            settings.flashMode = .off
        }

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

            guard let back, let front else {
                captureLock.unlock()
                return
            }

            main = mainIsBack ? back : front
            secondary = mainIsBack ? front : back

        case .single:

            guard let image = mainIsBack ? back : front else {
                captureLock.unlock()
                return
            }

            main = image
            secondary = nil
        }

        let completion = captureCompletion
        captureCompletion = nil
        isCapturing = false

        captureLock.unlock()

        // Kill the light the instant the photo exists, not on a timer.
        endFlash()

        DispatchQueue.main.async { [weak self] in

            guard let self else {
                return
            }

            self.capturedMainImage = main
            self.capturedSecondaryImage = secondary

            completion?()
        }
    }
}

// MARK: - Photo Delegate

extension CameraManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {

        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {

            captureLock.lock()
            isCapturing = false
            captureCompletion = nil
            captureLock.unlock()

            endFlash()
            return
        }

        captureLock.lock()

        if output === backOutput {
            backCaptureImage = image
        } else if output === frontOutput {
            frontCaptureImage = image
        }

        captureLock.unlock()

        finishCaptureIfReady()
    }
}
