import SwiftUI

struct PreferencesSettingsView: View {
    @EnvironmentObject var auth: AuthManager

    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearanceMode.system.rawValue
    @Environment(\.systemColorScheme) private var systemColorScheme // CHANGED: Uses custom key

    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var resolvedColorScheme: ColorScheme {
        let mode = AppearanceMode(rawValue: appearanceRaw) ?? .system
        switch mode {
        case .system: return systemColorScheme
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var body: some View {
        Form {
            if let message = auth.errorMessage {
                Section {
                    Text(message).foregroundColor(.red)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            }
            
            Section("About") {
                NavigationLink("Legal & Support") {
                    LegalSupportView()
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(resolvedColorScheme)
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

struct LegalSupportView: View {
    var body: some View {
        Form {
            Section {
                Link("Terms of Service", destination: URL(string: "https://oliversbee2.wixsite.com/framed/terms-of-service")!)
                Link("Privacy Policy", destination: URL(string: "https://oliversbee2.wixsite.com/framed/privacy-policyy")!)
            }
            
            Section {
                Link("Contact Support", destination: URL(string: "mailto:beeapps1234@outlook.com")!)
            }
        }
        .navigationTitle("Legal & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}