import Foundation

/// Uygulama yapılandırma yöneticisi
/// API anahtarları ve hassas bilgiler için güvenli erişim sağlar
enum Config {
    
    // MARK: - Private Configuration Loading
    
    private static let config: [String: Any] = {
        // Config.plist dosyasını yükle
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("⚠️ UYARI: Config.plist bulunamadı. Varsayılan değerler kullanılacak.")
            return [:]
        }
        return dict
    }()
    
    // MARK: - Gemini Configuration
    
    /// Google Gemini API Anahtarı
    static var geminiApiKey: String {
        if let key = config["GeminiAPIKey"] as? String, !key.isEmpty {
            return key
        }
        // Fallback: Geliştirme ortamı için
        return "YOUR_GEMINI_API_KEY"
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
        return "YOUR_SUPABASE_URL"
    }
    
    /// Supabase Anonymous Key
    static var supabaseAnonKey: String {
        if let key = config["SupabaseAnonKey"] as? String, !key.isEmpty {
            return key
        }
        return "YOUR_SUPABASE_ANON_KEY"
    }
    
    // MARK: - Validation
    
    /// Tüm yapılandırmaların geçerli olup olmadığını kontrol eder
    static func validateConfiguration() -> Bool {
        let geminiValid = geminiApiKey != "YOUR_GEMINI_API_KEY" && !geminiApiKey.isEmpty
        let supabaseUrlValid = supabaseUrl != "YOUR_SUPABASE_URL" && !supabaseUrl.isEmpty
        let supabaseKeyValid = supabaseAnonKey != "YOUR_SUPABASE_ANON_KEY" && !supabaseAnonKey.isEmpty
        
        if !geminiValid {
            print("❌ Gemini API anahtarı yapılandırılmamış")
        }
        if !supabaseUrlValid {
            print("❌ Supabase URL yapılandırılmamış")
        }
        if !supabaseKeyValid {
            print("❌ Supabase Anon Key yapılandırılmamış")
        }
        
        return geminiValid && supabaseUrlValid && supabaseKeyValid
    }
}
