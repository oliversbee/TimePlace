import SwiftUI

struct CaptureHomeView: View {
    @EnvironmentObject var auth: AuthManager

    @StateObject private var camera = CameraManager()
    
    // 1. Added HouseholdManager here to preload and share
    @StateObject private var householdManager = HouseholdManager()
    
    @State private var showPreview = false
    @State private var showSettings = false
    
    // State to control the success card
    @State private var showUploadSuccess = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            cameraContent
                .ignoresSafeArea()
            
            // =========================================================
            // UPLOAD SUCCESS OVERLAY
            // =========================================================
            if showUploadSuccess {
                UploadSuccessCard {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showUploadSuccess = false
                    }
                }
                .zIndex(10) // Ensures it sits above the camera view
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 40)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    )
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(auth)
                // 2. Pass the preloaded manager to Settings
                .environmentObject(householdManager)
        }
        // 3. Preload household and frame data on launch
        .task {
            await preloadUserData()
        }
        // Listens for changes to trigger the auto-dismiss timer
        .onChange(of: showUploadSuccess) { isShowing in
            if isShowing {
                Task {
                    // Wait 3 seconds
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    
                    // Dismiss if still showing
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showUploadSuccess = false
                        }
                    }
                }
            }
        }
    }
    
    private func preloadUserData() async {
        guard auth.userId != nil else { return }
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await householdManager.fetchHouseholds()
            }
            group.addTask {
                await householdManager.fetchPairedDevices()
            }
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        CameraCaptureView(
            camera: camera,

            // Open Settings directly
            onOpenMenu: {
                showSettings = true
            },

            onCaptured: {
                showPreview = true
            }
        )
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
                        // 1. Clear the images
                        camera.capturedMainImage = nil
                        camera.capturedSecondaryImage = nil
                        
                        // 2. Dismiss the preview full screen cover
                        showPreview = false
                        
                        // 3. Trigger the success card overlay
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showUploadSuccess = true
                        }
                    }
                )
                .environmentObject(auth)
            }
        }
    }
}

// =========================================================================
// UPLOAD SUCCESS CARD
// =========================================================================
struct UploadSuccessCard: View {
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Dimmed background to keep focus on the card while still seeing the camera
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 20) {
                // Green Checkmark
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Text (Single line)
                Text("Upload Complete")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            // More transparent, frosted glass effect
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.2)) // Slight dark tint for contrast
            .environment(\.colorScheme, .dark) 
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Wider card by reducing horizontal padding
            .padding(.horizontal, 24)
            .onTapGesture {
                onDismiss()
            }
        }
    }
}