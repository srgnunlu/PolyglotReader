import Foundation
import Combine
import AuthenticationServices
import SwiftUI

// MARK: - Auth ViewModel
@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentUser: User?

    private let supabaseService = SupabaseService.shared
    private var currentNonce: String?
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.addObserver(
            forName: SecurityManager.Notifications.requiresReauthentication,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.currentUser = nil
            self?.isAuthenticated = false
            self?.errorMessage = NSLocalizedString("auth.session_expired", comment: "")
        }

        supabaseService.$currentUser
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
            .store(in: &cancellables)

        Task {
            await checkExistingSession()
        }

        #if DEBUG
        MemoryDebugger.shared.logInit(self)
        #endif
    }

    deinit {
        #if DEBUG
        // Log deinit immediately without creating a Task that could hold references
        print("[MemoryDebugger] [DEINIT] AuthViewModel")
        #endif
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }

    // MARK: - Check Existing Session

    func checkExistingSession() async {
        isLoading = true
        defer { isLoading = false }

        if let user = await supabaseService.getSession() {
            currentUser = user
            isAuthenticated = true
        }
    }

    // MARK: - Google Sign In (Supabase OAuth)

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await supabaseService.signInWithOAuth(provider: "google")

            // Check if session was created after OAuth
            if let user = await supabaseService.getSession() {
                currentUser = user
                isAuthenticated = true
            }
        } catch {
            handleAuthError(error, operation: "GoogleSignIn") { [weak self] in
                Task { await self?.signInWithGoogle() }
                return
            }
            logError("AuthViewModel", "Google Sign In error", error: error)
        }
    }

    // MARK: - Apple Sign In

    func signInWithApple() {
        currentNonce = randomNonceString()

        guard let nonce = currentNonce else { return }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        _ = ASAuthorizationController(authorizationRequests: [request])
        // Note: In a real app, you'd set the delegate and present this controller
        // This is a simplified version - full implementation requires UIKit integration
    }

    func handleAppleSignIn(authorization: ASAuthorization) async {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8),
              let nonce = currentNonce else {
            errorMessage = NSLocalizedString("auth.apple_sign_in_failed", comment: "")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.signInWithApple(idToken: tokenString, nonce: nonce)
            currentUser = supabaseService.currentUser
            isAuthenticated = true
            errorMessage = nil
        } catch {
            handleAuthError(error, operation: "AppleSignIn") { [weak self] in
                Task { await self?.handleAppleSignIn(authorization: authorization) }
                return
            }
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            handleAuthError(error, operation: "SignOut") { [weak self] in
                Task { await self?.signOut() }
                return
            }
        }
    }

    private func handleAuthError(
        _ error: Error,
        operation: String,
        retryAction: (() -> Void)? = nil
    ) {
        let appError = ErrorHandlingService.mapToAppError(error)
        errorMessage = appError.localizedDescription
        ErrorHandlingService.shared.handle(
            appError,
            context: .init(
                source: "AuthViewModel",
                operation: operation,
                retryAction: retryAction
            )
        )
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// For SHA256 - need to import CommonCrypto
import CommonCrypto
