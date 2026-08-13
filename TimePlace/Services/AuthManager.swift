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

    private let client = SupabaseManager.shared.client

    init() {
        Task { await restoreSession() }
    }

    /// Restores a previously persisted session on app launch, if one exists.
    func restoreSession() async {
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
}
