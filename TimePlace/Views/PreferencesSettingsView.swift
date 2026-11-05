import SwiftUI

struct PreferencesSettingsView: View {
    @EnvironmentObject var auth: AuthManager

    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue

    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            // Account deletion errors
            if let message = auth.errorMessage {
                Section {
                    Text(message).foregroundColor(.red)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases.filter { $0 != .system }) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            }
            
            // Cleaned up Legal & Support section
            Section("About") {
                NavigationLink("Legal & Support") {
                    LegalSupportView()
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(appearanceBinding.wrappedValue.colorScheme)
        // Pinned to the bottom
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    if isDeleting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Deleting…")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else {
                        Text("Delete Account")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
                .disabled(isDeleting)
            }
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await auth.deleteAccount()
                    isDeleting = false
                }
            }
        } message: {
            Text("This permanently deletes your account, your photos and your household memberships. This can't be undone.")
        }
    }
}

// NEW: The nested view for the legal links
struct LegalSupportView: View {
    var body: some View {
        Form {
            Section {
                Link("Terms of Service", destination: URL(string: "https://yourdomain.com/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://yourdomain.com/privacy")!)
            }
            
            Section {
                Link("Contact Support", destination: URL(string: "mailto:support@yourdomain.com")!)
            }
        }
        .navigationTitle("Legal & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}