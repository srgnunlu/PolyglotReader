import CryptoKit
import Foundation
import Security
import Supabase

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Centralized security coordinator for config integrity, session security, and network pinning.
final class SecurityManager {
    /// Shared singleton instance.
    static let shared = SecurityManager()

    /// Security-related notifications.
    enum Notifications {
        static let requiresReauthentication = Notification.Name("SecurityRequiresReauthentication")
        static let pinningFailed = Notification.Name("SecurityPinningFailed")
        static let configTampered = Notification.Name("SecurityConfigTampered")
        static let jailbreakDetected = Notification.Name("SecurityJailbreakDetected")
    }

    /// Default timeout for requests.
    let requestTimeout: TimeInterval = 30
    /// Default timeout for resources.
    let resourceTimeout: TimeInterval = 60
    /// Extended timeout for large file uploads (5 minutes).
    let uploadTimeout: TimeInterval = 300
    /// Extended resource timeout for uploads (10 minutes).
    let uploadResourceTimeout: TimeInterval = 600
    /// Token refresh threshold in seconds.
    let refreshLeadTime: TimeInterval = 120
    /// Background session timeout in seconds.
    let backgroundSessionTimeout: TimeInterval = 15 * 60

    /// Secure URLSession with hardened configuration.
    let secureSession: URLSession
    
    /// Extended timeout URLSession for large file uploads.
    let uploadSession: URLSession

    private let keychainService = KeychainService.shared
    private var isConfigured = false
    private weak var supabaseClient: SupabaseClient?
    private var sessionRefreshTask: Task<Void, Never>?
    private var lastBackgroundDate: Date?

    private init() {
        // Standard secure session
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        secureSession = URLSession(configuration: configuration)
        
        // Extended timeout session for large file uploads
        let uploadConfiguration = URLSessionConfiguration.ephemeral
        uploadConfiguration.waitsForConnectivity = true
        uploadConfiguration.timeoutIntervalForRequest = uploadTimeout
        uploadConfiguration.timeoutIntervalForResource = uploadResourceTimeout
        uploadConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        uploadConfiguration.urlCache = nil
        uploadConfiguration.httpCookieStorage = nil
        uploadSession = URLSession(configuration: uploadConfiguration)
    }

    /// One-time security initialization.
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        if Self.isPinningEnabled {
            let pinningConfig = makePinningConfiguration()
            PinnedURLProtocol.configure(
                configuration: pinningConfig,
                requestTimeout: requestTimeout,
                resourceTimeout: resourceTimeout
            )
            _ = URLProtocol.registerClass(PinnedURLProtocol.self)
        }

        migrateLegacySession()
        _ = verifyConfigIntegrity()
        _ = Config.validateConfiguration()
        observeAppLifecycle()
        detectJailbreakIfNeeded()
    }

    /// Supplies a Keychain-backed storage for Supabase auth sessions.
    func makeSupabaseAuthStorage() -> AuthLocalStorage {
        let prompt: String?
        switch sessionAccessControl {
        case .none:
            prompt = nil
        case .userPresence, .biometryCurrentSet:
            prompt = "Authenticate to continue."
        }
        return KeychainAuthStorage(
            keychain: keychainService,
            accessControl: sessionAccessControl,
            prompt: prompt
        )
    }

    /// Registers the active Supabase client for session management.
    func registerSupabaseClient(_ client: SupabaseClient) {
        supabaseClient = client
    }

    /// Refreshes the session if it is near expiry.
    func refreshSessionIfNeeded(
        client: SupabaseClient,
        session: Session
    ) async -> Session? {
        let expiresAt = Date(timeIntervalSince1970: session.expiresAt)
        if expiresAt.timeIntervalSinceNow <= refreshLeadTime {
            do {
                let refreshed = try await client.auth.refreshSession(refreshToken: session.refreshToken)
                scheduleSessionRefresh(for: refreshed, client: client)
                return refreshed
            } catch {
                logWarning(
                    "SecurityManager",
                    "Session refresh failed",
                    details: error.localizedDescription
                )
                await forceLogout(reason: "refresh_failed")
                return nil
            }
        }

        scheduleSessionRefresh(for: session, client: client)
        return session
    }

    /// Clears secure storage and cached sensitive data.
    func clearSensitiveData() {
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil

        do {
            try keychainService.clearAll()
        } catch {
            logWarning(
                "SecurityManager",
                "Keychain clear failed",
                details: error.localizedDescription
            )
        }

        UserDefaults.standard.removeObject(forKey: Self.legacySessionKey)
        UserDefaults.standard.removeObject(forKey: Self.legacySessionKeyV1)
        URLCache.shared.removeAllCachedResponses()
    }

    // MARK: - Private Helpers

    private static let legacySessionKey = "supabase.auth.token"
    private static let legacySessionKeyV1 = "supabase.session"
    private static let configHashInfoKey = "ConfigPlistSHA256"
    private static let supabasePinsInfoKey = "SupabasePinnedKeys"
    private static let geminiPinsInfoKey = "GeminiPinnedKeys"
    private static let geminiHost = "generativelanguage.googleapis.com"

#if DEBUG
    // Development: pinning disabled
    static let isPinningEnabled = false
#else
    // Release: pinning enabled
    static let isPinningEnabled = true
#endif

    private let sessionAccessControl: KeychainService.AccessControl = .none

    private func scheduleSessionRefresh(for session: Session, client: SupabaseClient) {
        sessionRefreshTask?.cancel()

        let refreshTime = session.expiresAt - Date().timeIntervalSince1970 - refreshLeadTime
        let delay = max(0, refreshTime)
        let delayNanoseconds = UInt64(delay * 1_000_000_000)

        sessionRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard let self else { return }
            do {
                let refreshed = try await client.auth.refreshSession(refreshToken: session.refreshToken)
                self.scheduleSessionRefresh(for: refreshed, client: client)
            } catch {
                logWarning(
                    "SecurityManager",
                    "Scheduled refresh failed",
                    details: error.localizedDescription
                )
                await self.forceLogout(reason: "scheduled_refresh_failed")
            }
        }
    }

    private func forceLogout(reason: String) async {
        if let client = supabaseClient {
            try? await client.auth.signOut()
        }
        clearSensitiveData()
        logWarning("SecurityManager", "Session cleared", details: reason)
        NotificationCenter.default.post(name: Notifications.requiresReauthentication, object: nil)
    }

    private func migrateLegacySession() {
        let defaults = UserDefaults.standard
        let legacyKeys = [Self.legacySessionKey, Self.legacySessionKeyV1]

        for key in legacyKeys {
            guard let data = defaults.data(forKey: key) else { continue }
            do {
                try keychainService.store(data, for: key, accessControl: sessionAccessControl)
                defaults.removeObject(forKey: key)
            } catch {
                logWarning(
                    "SecurityManager",
                    "Legacy session migration failed",
                    details: error.localizedDescription
                )
            }
        }
    }

    private func verifyConfigIntegrity() -> Bool {
#if DEBUG
        return true
#else
        guard let expectedHash = Bundle.main.object(forInfoDictionaryKey: Self.configHashInfoKey) as? String,
              !expectedHash.isEmpty else {
            logWarning("SecurityManager", "Config hash missing")
            return true
        }

        if expectedHash == "REPLACE_WITH_CONFIG_SHA256" {
            logWarning("SecurityManager", "Config hash placeholder in use")
            return true
        }

        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") else {
            logError("SecurityManager", "Config.plist not found")
            return false
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: data)
            let hashString = hash.map { String(format: "%02x", $0) }.joined()

            if hashString.lowercased() != expectedHash.lowercased() {
                logError("SecurityManager", "Config hash mismatch")
                NotificationCenter.default.post(name: Notifications.configTampered, object: nil)
                return false
            }

            return true
        } catch {
            logError("SecurityManager", "Config hash computation failed", error: error)
            return false
        }
#endif
    }

    private func observeAppLifecycle() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        #elseif canImport(AppKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        #endif
    }

    @objc private func handleDidEnterBackground() {
        lastBackgroundDate = Date()
    }

    @objc private func handleDidBecomeActive() {
        guard let lastBackgroundDate else { return }
        let elapsed = Date().timeIntervalSince(lastBackgroundDate)
        self.lastBackgroundDate = nil

        guard elapsed >= backgroundSessionTimeout else { return }

        Task { [weak self] in
            await self?.forceLogout(reason: "background_timeout")
        }
    }

    private func detectJailbreakIfNeeded() {
        #if os(iOS)
        if isJailbroken() {
            logWarning("SecurityManager", "Jailbreak detected")
            NotificationCenter.default.post(name: Notifications.jailbreakDetected, object: nil)
        }
        #endif
    }

    #if os(iOS)
    private func isJailbroken() -> Bool {
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt"
        ]

        for path in suspiciousPaths where FileManager.default.fileExists(atPath: path) {
            return true
        }

        let testPath = "/private/jailbreak_check.txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
    }
    #endif

    private func makePinningConfiguration() -> PinningConfiguration {
        var enforcedHosts: Set<String> = []

        if let supabaseHost = URL(string: Config.supabaseUrl)?.host {
            enforcedHosts.insert(supabaseHost)
        }
        enforcedHosts.insert(Self.geminiHost)

        let supabasePins = loadPins(fromInfoKey: Self.supabasePinsInfoKey)
        let geminiPins = loadPins(fromInfoKey: Self.geminiPinsInfoKey)

        var pinsByHost: [String: Set<Data>] = [:]
        if let supabaseHost = URL(string: Config.supabaseUrl)?.host, !supabasePins.isEmpty {
            pinsByHost[supabaseHost] = supabasePins
        }
        if !geminiPins.isEmpty {
            pinsByHost[Self.geminiHost] = geminiPins
        }

        return PinningConfiguration(
            enforcedHosts: enforcedHosts,
            pinsByHost: pinsByHost,
            allowUnpinnedHostsInDebug: Self.allowUnpinnedHostsInDebug
        )
    }

    private func loadPins(fromInfoKey key: String) -> Set<Data> {
        let pins = Bundle.main.object(forInfoDictionaryKey: key) as? [String] ?? []
        return Set(pins.compactMap { Data(base64Encoded: $0) })
    }

    private static var allowUnpinnedHostsInDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
