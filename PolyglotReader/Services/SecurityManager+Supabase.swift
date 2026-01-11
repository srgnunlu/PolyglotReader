import Foundation
import Supabase

// MARK: - Keychain-backed Supabase Storage

struct KeychainAuthStorage: AuthLocalStorage {
    let keychain: KeychainService
    let accessControl: KeychainService.AccessControl
    let prompt: String?

    func store(key: String, value: Data) throws {
        try keychain.store(value, for: key, accessControl: accessControl)
    }

    func retrieve(key: String) throws -> Data? {
        do {
            return try keychain.readData(for: key, prompt: prompt)
        } catch KeychainService.KeychainError.itemNotFound {
            return nil
        } catch KeychainService.KeychainError.accessDenied {
            try? keychain.delete(key)
            NotificationCenter.default.post(
                name: SecurityManager.Notifications.requiresReauthentication,
                object: nil
            )
            return nil
        }
    }

    func remove(key: String) throws {
        try keychain.delete(key)
    }
}

// MARK: - Supabase Logger Adapter

struct SupabaseLoggerAdapter: SupabaseLogger {
    func log(message: SupabaseLogMessage) {
        let details = sanitizeDetails(message.description)

        switch message.level {
        case .verbose, .debug:
            guard shouldLogDebug(message) else { return }
            logDebug("Supabase", message.message, details: details)
        case .warning:
            logWarning("Supabase", message.message, details: details)
        case .error:
            logError("Supabase", details, error: nil)
        }
    }

    private func shouldLogDebug(_ message: SupabaseLogMessage) -> Bool {
        let description = message.description.lowercased()
        
        // Session yönetimi loglarını atla
        if description.contains("sessionmanager") {
            return false
        }
        
        let messageText = message.message.lowercased()
        if messageText.contains("session missing") || messageText.contains("sessionmissing") {
            return false
        }
        
        // RAG/Embedding request'lerini atla (çok fazla data içeriyor)
        if description.contains("match_chunks") || 
           description.contains("match_image_captions") ||
           description.contains("query_embedding") {
            return false
        }
        
        return true
    }
    
    private func sanitizeDetails(_ details: String) -> String {
        // Embedding array'lerini kısalt
        let embeddingPattern = "\"(query_embedding|embedding|caption_embedding)\"\\s*:\\s*\\[[\\s\\S]*?\\]"
        if let regex = try? NSRegularExpression(pattern: embeddingPattern, options: .dotMatchesLineSeparators) {
            let range = NSRange(details.startIndex..<details.endIndex, in: details)
            let sanitized = regex.stringByReplacingMatches(
                in: details,
                range: range,
                withTemplate: "\"$1\": [<768 dim vector omitted>]"
            )
            
            // Uzun body'leri kısalt
            if sanitized.count > 500 {
                return String(sanitized.prefix(500)) + "... <truncated \(sanitized.count - 500) chars>"
            }
            return sanitized
        }
        
        // Regex başarısız olursa, uzun string'leri kısalt
        if details.count > 500 {
            return String(details.prefix(500)) + "... <truncated \(details.count - 500) chars>"
        }
        
        return details
    }
}
