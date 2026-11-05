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
        NotificationManager.shared.cancelAllPrompts() // NEW: Cancel pending reminders
    }

    func deleteAccount() async {
        isLoading = true
        errorMessage = nil

        do {
            // Runs server-side under the service-role key; the token in the
            // request identifies whose account is being deleted.
            _ = try await client.functions.invoke("delete-account")

            // Server user is gone; clear local session and pending reminders.
            NotificationManager.shared.cancelAllPrompts()
            try? await client.auth.signOut(scope: .local)

            isAuthenticated = false
            userId = nil
        } catch {
            errorMessage = "We couldn't delete your account. Please try again, or contact support."
        }

        isLoading = false
    }
}