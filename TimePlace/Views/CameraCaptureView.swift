import SwiftUI

struct CameraCaptureView: View {
    @ObservedObject var camera: CameraManager
    var onCaptured: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main, full-screen feed
            CameraPreview(layer: camera.mainIsBack ? camera.backPreviewLayer : camera.frontPreviewLayer)
                .ignoresSafeArea()

            // Secondary feed, small, bottom-right corner — only shown in "Both" mode.
            // Tap it to swap which camera is "main".
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
                HStack {
                    Picker("Mode", selection: $camera.captureMode) {
                        ForEach(CaptureMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .background(.black.opacity(0.35))
                    .cornerRadius(8)

                    Spacer()

                    // Flips which camera is active/main. Doubles as the only way
                    // to switch cameras in "One" mode, since there's no corner
                    // preview to tap there.
                    Button {
                        camera.swapMain()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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

                HStack {
                    Spacer()
                    Button {
                        camera.capturePhoto(completion: onCaptured)
                    } label: {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                            .overlay(Circle().fill(.white).frame(width: 64, height: 64))
                    }
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.black)
        .onAppear {
            camera.configure()
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }
}
