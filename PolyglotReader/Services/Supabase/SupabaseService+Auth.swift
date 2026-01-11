import Foundation

extension SupabaseService {
    // MARK: - Auth Delegation (Backward Compatibility)

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await perform(category: .auth) {
            try await auth.signInWithApple(idToken: idToken, nonce: nonce)
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        try await perform(category: .auth) {
            try await auth.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        }
    }

    func signInWithOAuth(provider: String) async throws {
        try await perform(category: .auth) {
            try await auth.signInWithOAuth(provider: provider)
        }
    }

    func signOut() async throws {
        try await perform(category: .auth) {
            try await auth.signOut()
        }
    }

    func getSession() async -> User? {
        await auth.getSession()
    }

    // MARK: - OAuth Callback (Backward Compatibility)

    func handleOAuthCallback(accessToken: String, refreshToken: String) async throws {
        try await perform(category: .auth) {
            try await auth.handleOAuthCallback(accessToken: accessToken, refreshToken: refreshToken)
        }
    }
}
