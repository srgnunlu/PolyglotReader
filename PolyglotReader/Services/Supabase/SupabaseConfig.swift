import Foundation
import Supabase

// MARK: - Supabase Configuration

/// Centralized Supabase configuration
enum SupabaseConfig {
    /// Supabase project URL
    static var url: URL {
        let urlString = Config.supabaseUrl
        if let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            return url
        }

        logError("SupabaseConfig", "Geçersiz Supabase URL", error: nil)

        if let fallback = URL(string: "https://invalid.supabase.local") {
            return fallback
        }

        return URL(fileURLWithPath: "/")
    }

    /// Supabase anonymous key
    static var anonKey: String {
        Config.supabaseAnonKey
    }

    /// OAuth redirect URL for mobile auth flows.
    static var oauthRedirectURL: URL? {
        guard let scheme = urlScheme, !scheme.isEmpty else {
            return nil
        }
        return URL(string: "\(scheme)://login-callback")
    }

    private static var urlScheme: String? {
        guard let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return nil
        }
        for type in types {
            if let schemes = type["CFBundleURLSchemes"] as? [String],
               let scheme = schemes.first,
               !scheme.isEmpty {
                return scheme
            }
        }
        return nil
    }

    /// Shared Supabase client instance
    static let client: SupabaseClient = {
        let securityManager = SecurityManager.shared
        securityManager.configure()
        let options = SupabaseClientOptions(
            auth: .init(
                storage: securityManager.makeSupabaseAuthStorage(),
                redirectToURL: oauthRedirectURL,
                autoRefreshToken: true,
                emitLocalSessionAsInitialSession: true
            ),
            global: .init(
                session: securityManager.secureSession,
                logger: SupabaseLoggerAdapter()
            )
        )

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: options
        )
    }()
}

// MARK: - Error Types

/// Supabase-specific errors
enum SupabaseError: LocalizedError {
    case invalidConfiguration(String)
    case authenticationRequired
    case networkError(Error)
    case databaseError(String)
    case storageError(String)
    case encodingError(String)
    case decodingError(String)
    case notFound(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg):
            return "Configuration Error: \(msg)"
        case .authenticationRequired:
            return "Authentication required"
        case .networkError(let error):
            return "Network Error: \(error.localizedDescription)"
        case .databaseError(let msg):
            return "Database Error: \(msg)"
        case .storageError(let msg):
            return "Storage Error: \(msg)"
        case .encodingError(let msg):
            return "Encoding Error: \(msg)"
        case .decodingError(let msg):
            return "Decoding Error: \(msg)"
        case .notFound(let msg):
            return "Not Found: \(msg)"
        case .unknown(let msg):
            return "Unknown Error: \(msg)"
        }
    }
}

// MARK: - Common Response Types

/// File record from database
struct FileRecord: Decodable {
    let id: String
    let name: String
    let size: Int
    let storage_path: String
    let created_at: String
    let summary: String?
    let folder_id: String?
    let ai_category: String?
}

/// File insert payload
struct FileInsert: Encodable {
    let user_id: String
    let name: String
    let storage_path: String
    let file_type: String
    let size: Int
}

/// Summary update payload
struct SummaryUpdate: Encodable {
    let summary: String
}

/// Date formatting helper
enum DateFormatting {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from string: String) -> Date {
        iso8601.date(from: string) ?? Date()
    }
}
