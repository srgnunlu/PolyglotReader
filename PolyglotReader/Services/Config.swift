import CryptoKit
import Foundation

/// Uygulama yapılandırma yöneticisi
/// API anahtarları ve hassas bilgiler için güvenli erişim sağlar
enum Config {
    // MARK: - Private Configuration Loading

    private static let config: [String: Any] = {
        // Config.plist dosyasını yükle
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            logWarning(
                "Config",
                "Config.plist bulunamadı",
                details: "Varsayılan değerler kullanılacak."
            )
            return [:]
        }
        return dict
    }()

    private static let placeholderGeminiKey = "YOUR_GEMINI_API_KEY"
    private static let placeholderSupabaseUrl = "YOUR_SUPABASE_URL"
    private static let placeholderSupabaseKey = "YOUR_SUPABASE_ANON_KEY"

    private static var allowFallbackValues: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Gemini Configuration

    /// Google Gemini API Anahtarı
    static var geminiApiKey: String {
        secureString(
            plainKey: "GeminiAPIKey",
            obfuscatedKey: "GeminiAPIKeyObfuscated",
            placeholder: placeholderGeminiKey
        )
    }

    /// Gemini Model Adı
    static var geminiModelName: String {
        config["GeminiModelName"] as? String ?? "gemini-1.5-pro"
    }

    // MARK: - Supabase Configuration

    /// Supabase Project URL
    static var supabaseUrl: String {
        if let url = config["SupabaseURL"] as? String, !url.isEmpty {
            return url
        }
        return placeholderSupabaseUrl
    }

    /// Supabase Anonymous Key
    static var supabaseAnonKey: String {
        secureString(
            plainKey: "SupabaseAnonKey",
            obfuscatedKey: "SupabaseAnonKeyObfuscated",
            placeholder: placeholderSupabaseKey
        )
    }

    // MARK: - Validation

    /// Tüm yapılandırmaların geçerli olup olmadığını kontrol eder
    static func validateConfiguration() -> Bool {
        let geminiValid = geminiApiKey != placeholderGeminiKey && !geminiApiKey.isEmpty
        let supabaseUrlValid = supabaseUrl != placeholderSupabaseUrl && !supabaseUrl.isEmpty
        let supabaseKeyValid = supabaseAnonKey != placeholderSupabaseKey && !supabaseAnonKey.isEmpty

        if !geminiValid {
            logError("Config", "Gemini API anahtarı yapılandırılmamış")
        }
        if !supabaseUrlValid {
            logError("Config", "Supabase URL yapılandırılmamış")
        }
        if !supabaseKeyValid {
            logError("Config", "Supabase Anon Key yapılandırılmamış")
        }

        return geminiValid && supabaseUrlValid && supabaseKeyValid
    }

    // MARK: - Secure Value Helpers

    private static func secureString(
        plainKey: String,
        obfuscatedKey: String,
        placeholder: String
    ) -> String {
        if let obfuscated = config[obfuscatedKey] as? String,
           let decoded = ConfigObfuscator.decode(obfuscated),
           !decoded.isEmpty {
            return decoded
        }

        if let value = config[plainKey] as? String, !value.isEmpty {
            if !allowFallbackValues {
                logWarning("Config", "Release build plaintext key kullanıyor", details: plainKey)
            }
            return value
        }

        return allowFallbackValues ? placeholder : ""
    }

    private enum ConfigObfuscator {
        private static let keyBytes: [UInt8] = {
            let bundleId = Bundle.main.bundleIdentifier ?? "PolyglotReader"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            let seed = "\(bundleId).\(build)"
            let hash = SHA256.hash(data: Data(seed.utf8))
            return Array(hash)
        }()

        static func decode(_ base64: String) -> String? {
            guard let data = Data(base64Encoded: base64) else { return nil }
            let decoded = xor(data: data, key: keyBytes)
            return String(data: decoded, encoding: .utf8)
        }

        private static func xor(data: Data, key: [UInt8]) -> Data {
            guard !key.isEmpty else { return data }
            var output = Data(count: data.count)
            for index in data.indices {
                output[index] = data[index] ^ key[index % key.count]
            }
            return output
        }
    }
}
