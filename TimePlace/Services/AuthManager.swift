import Foundation
import Supabase

/// Handles login for accounts that already exist in Supabase Auth.
/// There is intentionally no sign-up flow — accounts are created ahead of time
/// (e.g. via the Supabase dashboard or an admin script).
@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var userId: UUID?
    
    // 1. Add this to track if we are still checking the session on launch
    @Published var isInitializing = true

    private let client = SupabaseManager.shared.client

    init() {
        Task { await restoreSession() }
    }

    /// Restores a previously persisted session on app launch, if one exists.
    func restoreSession() async {
        defer { isInitializing = false } // 2. Ensure this is set to false whether it succeeds or fails
        
        if let session = try? await client.auth.session {
            userId = session.user.id
            isAuthenticated = true
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            userId = session.user.id
            isAuthenticated = true
        } catch {
            errorMessage = "Couldn't log in. Check your email and password."
        }
        isLoading = false
    }

    func signOut() async {
        try? await client.auth.signOut()
        isAuthenticated = false
        userId = nil
    }

    // MARK: - Dummy Account Deletion
    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        
        // Placeholder logic: Simulate network request
        print("Placeholder: Account deletion requested for user \(userId?.uuidString ?? "unknown")")
        
        // Simulate a short delay so the UI shows the loading state
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // For now, just sign the user out to complete the UI flow
        await signOut()
        
        isLoading = false
    }
}