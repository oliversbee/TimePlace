import SwiftUI

struct CameraCaptureView: View {
    @ObservedObject var camera: CameraManager
    var onOpenMenu: () -> Void
    var onCaptured: () -> Void

    @State private var isFlashOn = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main, full-screen feed
            CameraPreview(layer: camera.mainIsBack ? camera.backPreviewLayer : camera.frontPreviewLayer)
                .ignoresSafeArea()

            // Secondary feed, small, bottom-right corner — only shown in "Both" mode.
            if camera.captureMode == .both {
                CameraPreview(layer: camera.mainIsBack ? camera.frontPreviewLayer : camera.backPreviewLayer)
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 3))
                    .padding(.trailing, 20)
                    .padding(.bottom, 140)
                    .onTapGesture { camera.swapMain() }
                    .shadow(radius: 6)
            }

            VStack {
                // Top Overlay Controls Header
                HStack(alignment: .center) {
                    // Top Left: Settings Button
                    Button {
                        onOpenMenu()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())    

                    Spacer()

                    // Top Right Controls: Mode Selector + Camera Flip Toggle
                    HStack(spacing: 12) {
                        Picker("Mode", selection: $camera.captureMode) {
                            ForEach(CaptureMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                        .background(.black.opacity(0.35))
                        .cornerRadius(8)

                        // Camera Flip Button
                        Button {
                            camera.swapMain()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 50)

                if let error = camera.errorMessage {
                    Text(error)
                        .foregroundColor(.white)
                        .font(.footnote)
                        .padding()
                        .background(.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding()
                }

                Spacer()

                // Bottom Capture Controls
                HStack {
                    // Spacer to balance the right-side flash button
                    Spacer()
                        .frame(width: 44)

                    Spacer()

                    // Shutter Capture Button
                    Button {
                        camera.capturePhoto(completion: onCaptured)
                    } label: {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                            .overlay(Circle().fill(.white).frame(width: 64, height: 64))
                    }

                    Spacer()

                    // Bottom Right: Flash Toggle Button
                    Button {
                        isFlashOn.toggle()
                        // Set flash mode on CameraManager instance
                    } label: {
                        Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.title3)
                            .foregroundColor(isFlashOn ? .yellow : .white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black)
        .ignoresSafeArea() // Prevents safe area recalculation from revealing a white bar at the bottom
        .onAppear {
            camera.configure()
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }
}