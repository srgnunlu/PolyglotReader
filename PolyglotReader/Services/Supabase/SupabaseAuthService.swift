import Combine
import Foundation
import Supabase
import UIKit
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Auth service handling sign in, sign out, and session management
final class SupabaseAuthService: ObservableObject {
    // MARK: - Properties

    let client: SupabaseClient
    private let securityManager = SecurityManager.shared

    @Published var currentUser: User?
    @Published var isLoading: Bool = false

    // MARK: - Initialization

    init(client: SupabaseClient) {
        self.client = client
        securityManager.registerSupabaseClient(client)

        Task { [weak self] in
            await self?.initializeSession()
        }
    }

    private func initializeSession() async {
        let session = await fetchSession()
        await MainActor.run {
            self.currentUser = session.flatMap { self.mapUser($0.user) }
        }

        // Listen for auth changes
        for await _ in client.auth.authStateChanges {
            let session = await fetchSession()
            await MainActor.run {
                self.currentUser = session.flatMap { self.mapUser($0.user) }
            }
        }
    }

    // MARK: - Auth Methods

    func signInWithApple(idToken: String, nonce: String) async throws {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        let refreshedSession = await securityManager.refreshSessionIfNeeded(client: client, session: session) ?? session
        await MainActor.run {
            self.currentUser = self.mapUser(refreshedSession.user)
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
        )
        let refreshedSession = await securityManager.refreshSessionIfNeeded(client: client, session: session) ?? session
        await MainActor.run {
            self.currentUser = self.mapUser(refreshedSession.user)
        }
    }

    func signInWithOAuth(provider: String) async throws {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }

        guard let authProvider = Provider(rawValue: provider) else {
            throw SupabaseError.invalidConfiguration("Unsupported OAuth provider: \(provider)")
        }
        guard let redirectURL = SupabaseConfig.oauthRedirectURL else {
            throw SupabaseError.invalidConfiguration("OAuth redirect URL is missing")
        }

        logInfo("SupabaseAuthService", "OAuth akışı başlatıldı", details: authProvider.rawValue)
        let session = try await signInWithOAuthSession(
            provider: authProvider,
            redirectURL: redirectURL
        )
        let refreshedSession = await securityManager.refreshSessionIfNeeded(client: client, session: session) ?? session
        await MainActor.run {
            self.currentUser = self.mapUser(refreshedSession.user)
        }
    }

    private func signInWithOAuthSession(
        provider: Provider,
        redirectURL: URL
    ) async throws -> Session {
        #if canImport(AuthenticationServices)
        let presentationContextProvider = OAuthPresentationContextProvider()
        return try await client.auth.signInWithOAuth(
            provider: provider,
            redirectTo: redirectURL
        ) { session in
            session.presentationContextProvider = presentationContextProvider
        }
        #else
        throw SupabaseError.invalidConfiguration("OAuth is not supported on this platform")
        #endif
    }

    func handleOAuthCallback(accessToken: String, refreshToken: String) async throws {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }

        let session = try await client.auth.setSession(
            accessToken: accessToken,
            refreshToken: refreshToken
        )
        let refreshedSession = await securityManager.refreshSessionIfNeeded(client: client, session: session) ?? session
        await MainActor.run {
            self.currentUser = self.mapUser(refreshedSession.user)
        }
    }

    func signOut() async throws {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }

        try await client.auth.signOut()
        securityManager.clearSensitiveData()
        await MainActor.run {
            self.currentUser = nil
        }
    }

    func getSession() async -> User? {
        let session = await fetchSession()
        await MainActor.run {
            self.currentUser = session.flatMap { self.mapUser($0.user) }
        }
        return currentUser
    }

    // MARK: - Private Helpers

    private func mapUser(_ authUser: Supabase.User) -> User {
        let metadata = authUser.userMetadata
        let name = metadataString(metadata, key: "full_name") ??
            metadataString(metadata, key: "name") ??
            extractUserName(from: authUser)
        let avatarString = metadataString(metadata, key: "avatar_url")
        let avatarURL = avatarString.flatMap { URL(string: $0) }

        return User(
            id: authUser.id.uuidString,
            name: name,
            email: authUser.email ?? "",
            avatarURL: avatarURL
        )
    }

    private func extractUserName(from authUser: Supabase.User) -> String {
        if let email = authUser.email {
            return email.components(separatedBy: "@").first ?? "User"
        }
        return "User"
    }

    private func metadataString(_ metadata: [String: AnyJSON], key: String) -> String? {
        guard let value = metadata[key] else { return nil }

        switch value {
        case .string(let string):
            return string
        case .double(let number):
            return String(number)
        default:
            return nil
        }
    }

    private func fetchSession() async -> Session? {
        do {
            let session = try await client.auth.session
            return await securityManager.refreshSessionIfNeeded(client: client, session: session) ?? session
        } catch AuthError.sessionMissing {
            return nil
        } catch {
            logWarning(
                "SupabaseAuthService",
                "Session alınamadı",
                details: error.localizedDescription
            )
            return nil
        }
    }
}

#if canImport(AuthenticationServices)
@MainActor
private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
        return window ?? ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
