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
    
    init() {
        Task {
            await checkExistingSession()
        }
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
            errorMessage = "Google ile giriş başarısız: \(error.localizedDescription)"
            print("Google Sign In error: \(error)")
        }
    }
    
    // MARK: - Apple Sign In
    
    func signInWithApple() {
        currentNonce = randomNonceString()
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(currentNonce!)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        // Note: In a real app, you'd set the delegate and present this controller
        // This is a simplified version - full implementation requires UIKit integration
    }
    
    func handleAppleSignIn(authorization: ASAuthorization) async {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8),
              let nonce = currentNonce else {
            errorMessage = "Apple ile giriş başarısız"
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
            errorMessage = "Giriş hatası: \(error.localizedDescription)"
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
            errorMessage = "Çıkış yapılamadı: \(error.localizedDescription)"
        }
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

