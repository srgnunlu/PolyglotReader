import Foundation
import Network
import GoogleGenerativeAI

// MARK: - Gemini Configuration
enum GeminiConfig {
    static let apiKey = Config.geminiApiKey
    static let modelName = Config.geminiModelName
    static let maxRetries = 3
    static let retryDelay: TimeInterval = 1.0
    static let maxRetryDelay: TimeInterval = 8.0
    private static let systemInstructionText = """
    Sen uzman düzeyinde bir akademik PDF doküman analizcisisin.
    Metni, tabloları, grafikleri ve görselleri derinlemesine analiz edebilirsin.

    ## TEMEL YETENEKLERİN:
    1. **Derinlemesine Analiz**: Akademik makaleleri, araştırma bulgularını ve
    metodolojileri detaylı analiz et
    2. **Görsel Yorumlama**: Grafik, tablo, diyagram ve şekilleri sayısal verilerle birlikte yorumla
    3. **Kritik Değerlendirme**: Bulguların güçlü ve zayıf yönlerini belirt
    4. **Bağlam Koruma**: Önceki konuşmaları hatırla ve tutarlı yanıtlar ver
    5. **Kaynak Gösterme**: Her önemli bilgi için [Sayfa X](jump:X) formatında referans ver
    6. **Karşılaştırmalı Analiz**: Farklı bölümler arasında bağlantı kur

    ## YANITLAMA KURALLARI:
    - Her zaman Türkçe yanıt ver
    - Markdown formatını etkin kullan (başlıklar, listeler, kalın/italik)
    - Sayısal verileri tablolarla göster
    - Belirsiz veya eksik bilgileri açıkça belirt
    - Uzun cevapları mantıklı bölümlere ayır
    - Önemli kavramları **kalın** olarak vurgula
    - Doğrudan alıntılarda "tırnak işareti" kullan

    ## KALİTE STANDARTLARI:
    - Spekülasyon yapma, sadece dokümandaki bilgilere dayan
    - İstatistiksel verileri doğru aktar (p-değeri, güven aralığı vb.)
    - Metodolojik detayları atla
    - Karmaşık kavramları basitçe açıkla
    """
    private static var systemInstruction: ModelContent {
        ModelContent(role: "system", parts: [.text(systemInstructionText)])
    }

    static func createModel() -> GenerativeModel {
        GenerativeModel(
            name: modelName,
            apiKey: apiKey,
            generationConfig: GenerationConfig(
                temperature: 0.3,
                topP: 0.85,
                topK: 40,
                maxOutputTokens: 16384
            ),
            systemInstruction: systemInstruction,
            requestOptions: RequestOptions(timeout: SecurityManager.shared.resourceTimeout)
        )
    }
}

// MARK: - Gemini Errors
enum GeminiError: Error, LocalizedError {
    case noResponse
    case parseError
    case sessionNotInitialized
    case rateLimitExceeded
    case quotaExhausted
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .noResponse:
            return "AI'dan yanıt alınamadı."
        case .parseError:
            return "Yanıt işlenemedi."
        case .sessionNotInitialized:
            return "Chat oturumu başlatılmadı."
        case .rateLimitExceeded:
            return "Çok fazla istek gönderildi. Lütfen bekleyin."
        case .quotaExhausted:
            return "Günlük kullanım limiti aşıldı."
        case .networkUnavailable:
            return "İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin."
        }
    }
}

// MARK: - Network Monitor
class GeminiNetworkMonitor {
    static let shared = GeminiNetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "GeminiNetworkMonitor")

    var isConnected: Bool = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Helper Functions
extension GeminiConfig {
    static func executeWithRetry<T>(
        serviceName: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await executeOnce(operation)
            } catch {
                lastError = error
                let normalizedError = normalizeError(error)

                logFailure(
                    serviceName: serviceName,
                    attempt: attempt,
                    error: error
                )

                if let geminiError = normalizedError, shouldAbortRetry(geminiError, attempt: attempt) {
                    throw geminiError
                }

                if attempt < maxRetries {
                    await sleepBeforeRetry(attempt: attempt)
                }
            }
        }

        if let normalizedError = lastError.flatMap(normalizeError) {
            throw normalizedError
        }
        throw lastError ?? GeminiError.noResponse
    }
}

private extension GeminiConfig {
    static func executeOnce<T>(_ operation: () async throws -> T) async throws -> T {
        guard GeminiNetworkMonitor.shared.isConnected else {
            throw GeminiError.networkUnavailable
        }
        return try await operation()
    }

    static func logFailure(serviceName: String, attempt: Int, error: Error) {
        #if DEBUG
        logWarning(
            "GeminiConfig",
            "Deneme \(attempt)/\(maxRetries) başarısız",
            details: "\(serviceName): \(error.localizedDescription)"
        )
        #endif
    }

    static func shouldAbortRetry(_ error: GeminiError, attempt: Int) -> Bool {
        switch error {
        case .quotaExhausted, .sessionNotInitialized, .networkUnavailable:
            return true
        case .rateLimitExceeded:
            return attempt == maxRetries
        default:
            return false
        }
    }

    static func sleepBeforeRetry(attempt: Int) async {
        let baseDelay = retryDelay * pow(2.0, Double(attempt - 1))
        let backoff = min(baseDelay, maxRetryDelay)
        let jitter = Double.random(in: 0...0.3)
        let delay = backoff + jitter
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    static func normalizeError(_ error: Error) -> GeminiError? {
        if let geminiError = error as? GeminiError {
            return geminiError
        }

        if error is URLError {
            return .networkUnavailable
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("quota") || description.contains("limit reached") {
            return .quotaExhausted
        }
        if description.contains("rate") || description.contains("too many requests") || description.contains("429") {
            return .rateLimitExceeded
        }
        if description.contains("timeout") || description.contains("timed out") {
            return .networkUnavailable
        }

        return nil
    }
}
