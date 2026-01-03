import Foundation
import Combine
import UIKit
import Supabase
import os.log

// MARK: - Supabase Configuration
enum SupabaseConfig {
    static let url = URL(string: Config.supabaseUrl)!
    static let anonKey = Config.supabaseAnonKey
}

// MARK: - RAG RPC Helper Structs (Outside MainActor for Sendable compliance)
private struct RAGSearchParams: Encodable, @unchecked Sendable {
    let query_embedding: String
    let match_file_id: String
    let match_count: Int
}

private struct RAGSearchResult: Decodable, @unchecked Sendable {
    let id: UUID
    let file_id: UUID
    let chunk_index: Int
    let content: String
    let page_number: Int?
    let similarity: Float
}
@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    let client: SupabaseClient
    
    @Published var currentUser: User?
    @Published var isLoading = false
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
    
    // MARK: - Debug Logging Helper
    private func writeDebugLog(_ data: [String: Any]) {
        // OSLog ile console'a yaz (Xcode Console'da görülebilir)
        let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "PolyglotReader", category: "Debug")
        if let location = data["location"] as? String,
           let message = data["message"] as? String {
            let dataStr = (data["data"] as? [String: Any])?.description ?? "nil"
            os_log("%{public}@: %{public}@ | Data: %{public}@", log: osLog, type: .debug, location, message, dataStr)
        }
        
        // Dosyaya da yaz (backup)
        guard let logJson = try? JSONSerialization.data(withJSONObject: data),
              let logString = String(data: logJson, encoding: .utf8) else { return }
        
        let logLine = logString + "\n"
        guard let logData = logLine.data(using: .utf8) else { return }
        
        // iOS Documents dizininde debug.log dosyasına yaz
        if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logURL = documentsDir.appendingPathComponent("debug.log")
            
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(logData)
                    handle.closeFile()
                }
            } else {
                try? logData.write(to: logURL)
            }
        }
    }
    
    // MARK: - Authentication
    
    func signInWithApple(idToken: String, nonce: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        
        await updateCurrentUser(from: session.user)
    }
    
    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
        )
        
        await updateCurrentUser(from: session.user)
    }
    
    // MARK: - OAuth Sign In (Browser-based)
    
    func signInWithOAuth(provider: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Get the OAuth URL from Supabase
        let redirectURL = URL(string: "polyglotreader://login-callback")!
        
        // Build OAuth URL manually
        var components = URLComponents(url: SupabaseConfig.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString)
        ]
        
        guard let url = components.url else {
            throw NSError(domain: "OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "OAuth URL oluşturulamadı"])
        }
        
        // Open the OAuth URL in the default browser
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
    
    func signOut() async throws {
        try await client.auth.signOut()
        currentUser = nil
    }
    
    func getSession() async -> User? {
        guard let session = try? await client.auth.session else { return nil }
        await updateCurrentUser(from: session.user)
        return currentUser
    }
    
    func handleOAuthCallback(accessToken: String, refreshToken: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let session = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
        await updateCurrentUser(from: session.user)
    }
    
    private func updateCurrentUser(from authUser: Supabase.User) async {
        let name = authUser.userMetadata["full_name"]?.stringValue ?? 
                   authUser.email?.components(separatedBy: "@").first ?? "Kullanıcı"
        
        currentUser = User(
            id: authUser.id.uuidString,
            name: name,
            email: authUser.email ?? ""
        )
    }
    
    // MARK: - File Operations
    
    func uploadFile(_ data: Data, fileName: String, userId: String) async throws -> PDFDocumentMetadata {
        // More robust sanitization: remove non-alphanumeric characters except dot and dash, and replace spaces with underscores
        let sanitizedName = fileName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "", options: .regularExpression)
        
        let storagePath = "\(userId.lowercased())/\(Int(Date().timeIntervalSince1970))_\(sanitizedName)"
        
        // Upload to Storage

        try await client.storage.from("user_files").upload(
            storagePath,
            data: data,
            options: .init(contentType: "application/pdf")
        )
        
        // Save metadata to Database
        struct FileInsert: Encodable {
            let user_id: String
            let name: String
            let storage_path: String
            let file_type: String
            let size: Int
        }
        
        let fileData = FileInsert(
            user_id: userId,
            name: fileName,
            storage_path: storagePath,
            file_type: "application/pdf",
            size: data.count
        )
        
        struct FileResponse: Decodable {
            let id: String
            let name: String
            let size: Int
            let storage_path: String
            let created_at: String
        }
        
        let response: FileResponse = try await client
            .from("files")
            .insert(fileData)
            .select()
            .single()
            .execute()
            .value
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let uploadedAt = dateFormatter.date(from: response.created_at) ?? Date()

        return PDFDocumentMetadata(
            id: response.id,
            name: response.name,
            size: response.size,
            uploadedAt: uploadedAt,
            storagePath: storagePath
        )
    }
    
    func listFiles() async throws -> [PDFDocumentMetadata] {
        struct FileRecord: Decodable {
            let id: String
            let name: String
            let size: Int
            let storage_path: String
            let created_at: String
            let summary: String?
            let folder_id: UUID?
            let ai_category: String?
        }
        
        let files: [FileRecord] = try await client
            .from("files")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return files.map { file in
            PDFDocumentMetadata(
                id: file.id,
                name: file.name,
                size: file.size,
                uploadedAt: dateFormatter.date(from: file.created_at) ?? Date(),
                storagePath: file.storage_path,
                summary: file.summary,
                folderId: file.folder_id,
                aiCategory: file.ai_category
            )
        }
    }
    
    // MARK: - Get Single File
    
    func getFile(id: String) async throws -> PDFDocumentMetadata? {
        struct FileRecord: Decodable {
            let id: String
            let name: String
            let size: Int
            let storage_path: String
            let created_at: String
            let summary: String?
        }
        
        let files: [FileRecord] = try await client
            .from("files")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        
        guard let file = files.first else { return nil }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return PDFDocumentMetadata(
            id: file.id,
            name: file.name,
            size: file.size,
            uploadedAt: dateFormatter.date(from: file.created_at) ?? Date(),
            storagePath: file.storage_path,
            summary: file.summary
        )
    }
    
    // MARK: - Update File Summary
    
    func updateFileSummary(fileId: String, summary: String) async throws {
        struct SummaryUpdate: Encodable {
            let summary: String
        }
        
        try await client
            .from("files")
            .update(SummaryUpdate(summary: summary))
            .eq("id", value: fileId)
            .execute()
    }
    
    func getFileURL(storagePath: String) async throws -> URL {
        logDebug("SupabaseService", "Getting file URL for path: \(storagePath)")
        
        let signedURL = try await client.storage
            .from("user_files")
            .createSignedURL(path: storagePath, expiresIn: 3600)
        
        logDebug("SupabaseService", "Got signed URL: \(signedURL)")
        return signedURL
    }
    
    func deleteFile(id: String, storagePath: String) async throws {
        // Delete from storage
        try await client.storage.from("user_files").remove(paths: [storagePath])
        
        // Delete from database
        try await client.from("files").delete().eq("id", value: id).execute()
    }
    
    // MARK: - Chat Operations
    
    func saveChatMessage(fileId: String, role: String, content: String) async throws {
        guard let userId = currentUser?.id else { throw NSError(domain: "Auth", code: 401) }
        
        struct ChatInsert: Encodable {
            let file_id: String
            let user_id: String
            let role: String
            let content: String
        }
        
        try await client.from("chats").insert(
            ChatInsert(file_id: fileId, user_id: userId, role: role, content: content)
        ).execute()
    }
    
    func getChatHistory(fileId: String) async throws -> [ChatMessage] {
        struct ChatRecord: Decodable {
            let id: String
            let role: String
            let content: String
            let created_at: String
        }
        
        let records: [ChatRecord] = try await client
            .from("chats")
            .select()
            .eq("file_id", value: fileId)
            .order("created_at", ascending: true)
            .execute()
            .value
        
        let dateFormatter = ISO8601DateFormatter()
        
        return records.compactMap { record in
            guard let role = ChatMessage.MessageRole(rawValue: record.role) else { return nil }
            return ChatMessage(
                id: record.id,
                role: role,
                text: record.content,
                timestamp: dateFormatter.date(from: record.created_at) ?? Date()
            )
        }
    }
    
    // MARK: - Annotation Operations
    
    func saveAnnotation(_ annotation: Annotation) async throws {
        _ = try await saveAnnotations([annotation])
    }

    func saveAnnotations(_ annotations: [Annotation]) async throws -> Int {
        // #region agent log
        let logData: [String: Any] = [
            "location": "SupabaseService.saveAnnotations:344",
            "message": "saveAnnotations başladı",
            "data": [
                "annotationCount": annotations.count,
                "userId": currentUser?.id ?? "nil"
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "A"
        ]
        writeDebugLog(logData)
        // #endregion
        
        guard let userId = currentUser?.id else { throw NSError(domain: "Auth", code: 401) }
        guard !annotations.isEmpty else { return 0 }
        
        // CRITICAL: safeForJSON çağrısını kaldırdık çünkü property'lere erişim crash'e neden oluyor
        // Annotation'ları direkt olarak compactMap içinde güvenli hale getireceğiz
        
        struct AnnotationData: Encodable {
            let color: String
            let rects: [AnnotationRect]
            let text: String?
            let note: String?
            let isAiGenerated: Bool
            
            // Güvenli encoding - String corruption'ı önlemek için
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(String(color), forKey: .color)
                try container.encode(rects, forKey: .rects)
                if let text = text {
                    try container.encode(String(text), forKey: .text)
                } else {
                    try container.encodeNil(forKey: .text)
                }
                if let note = note {
                    try container.encode(String(note), forKey: .note)
                } else {
                    try container.encodeNil(forKey: .note)
                }
                try container.encode(isAiGenerated, forKey: .isAiGenerated)
            }
            
            enum CodingKeys: String, CodingKey {
                case color, rects, text, note, isAiGenerated
            }
        }
        
        struct AnnotationInsert: Encodable {
            let id: String
            let file_id: String
            let user_id: String
            let page: Int
            let type: String
            let data: AnnotationData
            
            // Güvenli encoding - String corruption'ı önlemek için
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(String(id), forKey: .id)
                try container.encode(String(file_id), forKey: .file_id)
                try container.encode(String(user_id), forKey: .user_id)
                try container.encode(page, forKey: .page)
                try container.encode(String(type), forKey: .type)
                try container.encode(data, forKey: .data)
            }
            
            enum CodingKeys: String, CodingKey {
                case id, file_id, user_id, page, type, data
            }
        }
        
        // CRITICAL: Annotation'ları direkt olarak işle - safeForJSON çağrısı crash'e neden oluyor
        // Property'lere direkt erişim de crash'e neden oluyor, bu yüzden Mirror API kullanarak güvenli okuma yapıyoruz
        let inserts = annotations.enumerated().compactMap { index, annotation -> AnnotationInsert? in
            // #region agent log
            let logDataBefore: [String: Any] = [
                "location": "SupabaseService.saveAnnotations:481",
                "message": "compactMap başladı - annotation işleniyor",
                "data": [
                    "annotationIndex": index,
                    "annotationId": "processing" // annotation.id'ye erişmek crash'e neden olabilir
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "D1"
            ]
            writeDebugLog(logDataBefore)
            // #endregion
            
            // CRITICAL: Property'lere direkt erişim crash'e neden oluyor
            // Mirror API kullanarak property'leri güvenli bir şekilde oku
            let mirror = Mirror(reflecting: annotation)
            
            // Helper: Mirror'dan String property okuma
            // CRITICAL: child.value as? String crash'e neden o labilir çünkü string zaten bozuk
            // NSString bridge kullanarak güvenli okuma yap
            func safeReadString(from mirror: Mirror, key: String, fallback: String) -> String {
                for child in mirror.children {
                    if child.label == key {
                        // child.value'ya direkt erişim crash'e neden olabilir
                        // NSString bridge kullanarak güvenli okuma yap
                        let value = child.value
                        
                        // NSString'e bridge et - bu daha güvenli olabilir
                        if let nsString = value as? NSString {
                            let stringValue = nsString as String
                            // Şimdi String'i Data'ya çevirip tekrar String'e çevir (yeni memory allocation)
                            guard let data = stringValue.data(using: .utf8),
                                  let safeStr = String(data: data, encoding: .utf8) else {
                                return fallback
                            }
                            return safeStr
                        }
                        
                        // NSString bridge başarısız olursa, String(describing:) kullan
                        // Bu, value'nun string representation'ını oluşturur
                        let stringDescription = String(describing: value)
                        if stringDescription != "nil" && !stringDescription.isEmpty {
                            guard let data = stringDescription.data(using: .utf8),
                                  let safeStr = String(data: data, encoding: .utf8) else {
                                return fallback
                            }
                            return safeStr
                        }
                    }
                }
                return fallback
            }
            
            // Helper: Mirror'dan Int property okuma
            func safeReadInt(from mirror: Mirror, key: String, fallback: Int) -> Int {
                for child in mirror.children {
                    if child.label == key, let value = child.value as? Int {
                        return value
                    }
                }
                return fallback
            }
            
            // Helper: Mirror'dan Bool property okuma
            func safeReadBool(from mirror: Mirror, key: String, fallback: Bool) -> Bool {
                for child in mirror.children {
                    if child.label == key, let value = child.value as? Bool {
                        return value
                    }
                }
                return fallback
            }
            
            // Helper: Mirror'dan Optional String property okuma
            // CRITICAL: child.value as? String crash'e neden olabilir
            func safeReadOptionalString(from mirror: Mirror, key: String) -> String? {
                for child in mirror.children {
                    if child.label == key {
                        let value = child.value
                        
                        // NSNull kontrolü
                        if value is NSNull {
                            return nil
                        }
                        
                        // NSString bridge kullanarak güvenli okuma
                        if let nsString = value as? NSString {
                            let stringValue = nsString as String
                            guard let data = stringValue.data(using: .utf8),
                                  let safeStr = String(data: data, encoding: .utf8),
                                  !safeStr.isEmpty else {
                                return nil
                            }
                            return safeStr
                        }
                        
                        // String(describing:) fallback
                        let stringDescription = String(describing: value)
                        if stringDescription != "nil" && !stringDescription.isEmpty {
                            guard let data = stringDescription.data(using: .utf8),
                                  let safeStr = String(data: data, encoding: .utf8),
                                  !safeStr.isEmpty else {
                                return nil
                            }
                            return safeStr
                        }
                    }
                }
                return nil
            }
            
            // Helper: Mirror'dan AnnotationType okuma
            func safeReadType(from mirror: Mirror, fallback: AnnotationType) -> AnnotationType {
                for child in mirror.children {
                    if child.label == "type" {
                        if let type = child.value as? AnnotationType {
                            return type
                        }
                    }
                }
                return fallback
            }
            
            // Helper: Mirror'dan AnnotationRect array okuma
            func safeReadRects(from mirror: Mirror) -> [AnnotationRect] {
                for child in mirror.children {
                    if child.label == "rects", let rects = child.value as? [AnnotationRect] {
                        return rects
                    }
                }
                return []
            }
            
            // Tüm property'leri Mirror API ile güvenli bir şekilde oku
            let safeId = safeReadString(from: mirror, key: "id", fallback: UUID().uuidString)
            let safeFileId = safeReadString(from: mirror, key: "fileId", fallback: safeId)
            let safeColor = safeReadString(from: mirror, key: "color", fallback: "#fef08a")
            let safeType = safeReadType(from: mirror, fallback: .highlight)
            let safePageNumber = safeReadInt(from: mirror, key: "pageNumber", fallback: 1)
            let safeText = safeReadOptionalString(from: mirror, key: "text")
            let safeNote = safeReadOptionalString(from: mirror, key: "note")
            let safeIsAiGenerated = safeReadBool(from: mirror, key: "isAiGenerated", fallback: false)
            let safeRects = safeReadRects(from: mirror)
            
            // safeType'ı String'e çevir
            let safeTypeStr = safeType.rawValue
            
            // Text ve Note'u sanitize et
            let safeTextSanitized = safeText.map { sanitizeForStorage($0, maxLength: 2000) } ?? nil
            let safeNoteSanitized = safeNote.map { sanitizeForStorage($0, maxLength: 2000) } ?? nil
            
            // userId için de güvenli String oluştur
            let safeUserId: String = {
                guard let data = userId.data(using: .utf8),
                      let str = String(data: data, encoding: .utf8) else {
                    return userId // Fallback - userId zaten güvenli olmalı
                }
                return str
            }()
            
            // #region agent log
            let logData4: [String: Any] = [
                "location": "SupabaseService.saveAnnotations:368",
                "message": "Annotation işleniyor",
                "data": [
                    "annotationId": safeId,
                    "textLength": safeTextSanitized?.count ?? 0,
                    "noteLength": safeNoteSanitized?.count ?? 0,
                    "colorLength": safeColor.count
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "D"
            ]
            writeDebugLog(logData4)
            // #endregion
            
            // safeRects'i kullan (zaten Mirror'dan okundu)
            let validRects = safeRects.filter { $0.isValid }
            guard !validRects.isEmpty else { return nil }

            // #region agent log
            let logData6: [String: Any] = [
                "location": "SupabaseService.saveAnnotations:376",
                "message": "AnnotationInsert oluşturuluyor",
                "data": [
                    "safeTextIsNil": safeTextSanitized == nil,
                    "safeNoteIsNil": safeNoteSanitized == nil,
                    "safeColorLength": safeColor.count,
                    "safeIdLength": safeId.count,
                    "safeFileIdLength": safeFileId.count
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "F"
            ]
            writeDebugLog(logData6)
            // #endregion

            // #region agent log
            let logData7: [String: Any] = [
                "location": "SupabaseService.saveAnnotations:550",
                "message": "AnnotationInsert oluşturuluyor",
                "data": [
                    "safeIdLength": safeId.count,
                    "safeFileIdLength": safeFileId.count,
                    "safeColorLength": safeColor.count,
                    "safeTypeStr": safeTypeStr,
                    "safeTextIsNil": safeTextSanitized == nil,
                    "safeNoteIsNil": safeNoteSanitized == nil
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "E"
            ]
            writeDebugLog(logData7)
            // #endregion
            
            return AnnotationInsert(
                id: safeId,
                file_id: safeFileId,
                user_id: safeUserId,
                page: safePageNumber,
                type: safeTypeStr,
                data: AnnotationData(
                    color: safeColor,
                    rects: validRects,
                    text: safeTextSanitized,
                    note: safeNoteSanitized,
                    isAiGenerated: safeIsAiGenerated
                )
            )
        }
        
        // #region agent log
        let logData7: [String: Any] = [
            "location": "SupabaseService.saveAnnotations:392",
            "message": "Supabase insert çağrılıyor",
            "data": ["insertCount": inserts.count],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "G"
        ]
        writeDebugLog(logData7)
        // #endregion
        
        // CRITICAL: JSON encoding'i manuel yaparak String corruption'ı tamamen önle
        // Supabase client'ın otomatik encoding'i yerine manuel JSON oluştur
        guard !inserts.isEmpty else { return 0 }
        
        // #region agent log
        let logData8: [String: Any] = [
            "location": "SupabaseService.saveAnnotations:510",
            "message": "JSON encoding başlıyor",
            "data": ["insertCount": inserts.count],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "H"
        ]
        writeDebugLog(logData8)
        // #endregion
        
        // Güvenli JSON encoding
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = []
        
        do {
            let jsonData = try jsonEncoder.encode(inserts)
            
            // #region agent log
            let logData9: [String: Any] = [
                "location": "SupabaseService.saveAnnotations:520",
                "message": "JSON encoding tamamlandı",
                "data": ["jsonDataSize": jsonData.count],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "I"
            ]
            writeDebugLog(logData9)
            // #endregion
            
            // Supabase'e gönder
            try await client.from("annotations").insert(inserts).execute()
            return inserts.count
        } catch {
            // #region agent log
            let logData10: [String: Any] = [
                "location": "SupabaseService.saveAnnotations:530",
                "message": "JSON encoding hatası",
                "data": ["error": error.localizedDescription],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "J"
            ]
            writeDebugLog(logData10)
            // #endregion
            throw error
        }
    }

    private func sanitizeForStorage(_ value: String?, maxLength: Int) -> String? {
        // #region agent log
        let logData: [String: Any] = [
            "location": "SupabaseService.sanitizeForStorage:396",
            "message": "sanitizeForStorage başladı",
            "data": [
                "valueIsNil": value == nil,
                "valueLength": value?.count ?? 0,
                "maxLength": maxLength
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "H"
        ]
        writeDebugLog(logData)
        // #endregion
        
        guard let value, !value.isEmpty else { return nil }
        
        // #region agent log
        let logData2: [String: Any] = [
            "location": "SupabaseService.sanitizeForStorage:400",
            "message": "String işleme başladı",
            "data": ["valueLength": value.count],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "I"
        ]
        writeDebugLog(logData2)
        // #endregion
        
        // Güvenli String kopyalama - NSString yerine doğrudan String kullan
        let safeLength = min(value.count, maxLength)
        let truncated = String(value.prefix(safeLength))
        
        // #region agent log
        let logData3: [String: Any] = [
            "location": "SupabaseService.sanitizeForStorage:405",
            "message": "sanitizeForStorage tamamlandı",
            "data": ["truncatedLength": truncated.count],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "J"
        ]
        writeDebugLog(logData3)
        // #endregion
        
        return truncated
    }
    
    func getAnnotations(fileId: String) async throws -> [Annotation] {
        struct AnnotationData: Decodable {
            let color: String
            let rects: [AnnotationRect]
            let text: String?
            let note: String?
            let isAiGenerated: Bool?
        }
        
        struct AnnotationRecord: Decodable {
            let id: String
            let file_id: UUID  // UUID olarak parse et
            let page: Int
            let type: String
            let data: AnnotationData
            let created_at: String
        }
        
        let records: [AnnotationRecord] = try await client
            .from("annotations")
            .select()
            .eq("file_id", value: fileId)
            .execute()
            .value
        
        let dateFormatter = ISO8601DateFormatter()
        
        return records.compactMap { record in
            guard let type = AnnotationType(rawValue: record.type) else { return nil }
            return Annotation(
                id: record.id,
                fileId: record.file_id.uuidString,  // UUID'yi String'e çevir
                pageNumber: record.page,
                type: type,
                color: record.data.color,
                rects: record.data.rects,
                text: record.data.text,
                note: record.data.note,
                isAiGenerated: record.data.isAiGenerated ?? false,
                createdAt: dateFormatter.date(from: record.created_at) ?? Date()
            )
        }
    }
    
    /// Annotation sil
    func deleteAnnotation(id: String) async throws {
        try await client
            .from("annotations")
            .delete()
            .eq("id", value: id)
            .execute()
        
        logInfo("SupabaseService", "Annotation silindi", details: "ID: \(id)")
    }
    
    /// Annotation güncelle (not ekle/düzenle)
    func updateAnnotation(id: String, note: String?) async throws {
        struct AnnotationUpdate: Encodable {
            let data: AnnotationDataUpdate
        }
        
        struct AnnotationDataUpdate: Encodable {
            let note: String?
        }
        
        // Önce mevcut annotation'ı al
        struct AnnotationRecord: Decodable {
            let data: AnnotationData
        }
        
        struct AnnotationData: Codable {
            let color: String
            let rects: [AnnotationRect]
            let text: String?
            let note: String?
            let isAiGenerated: Bool?
            let updatedAt: Date?
        }
        
        let records: [AnnotationRecord] = try await client
            .from("annotations")
            .select("data")
            .eq("id", value: id)
            .execute()
            .value
        
        guard let existing = records.first else {
            throw NSError(domain: "Supabase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Annotation bulunamadı"])
        }
        
        // Mevcut data'yı güncellenmiş note ile birleştir
        let updatedData = AnnotationData(
            color: existing.data.color,
            rects: existing.data.rects,
            text: existing.data.text,
            note: note,
            isAiGenerated: existing.data.isAiGenerated,
            updatedAt: Date()
        )
        
        struct UpdatePayload: Encodable {
            let data: AnnotationData
        }
        
        try await client
            .from("annotations")
            .update(UpdatePayload(data: updatedData))
            .eq("id", value: id)
            .execute()
        
        logInfo("SupabaseService", "Annotation güncellendi", details: "ID: \(id)")
    }
    
    /// Kullanıcının tüm annotation'larını al (Notebook için)
    func getAllAnnotations() async throws -> [(annotation: Annotation, fileName: String, isFavorite: Bool)] {
        struct AnnotationData: Decodable {
            let color: String
            let rects: [AnnotationRect]
            let text: String?
            let note: String?
            let isAiGenerated: Bool?
        }

        struct FileInfo: Decodable {
            let name: String
        }

        struct AnnotationWithFile: Decodable {
            let id: String
            let file_id: UUID  // UUID olarak parse et
            let page: Int
            let type: String
            let data: AnnotationData
            let created_at: String
            let is_favorite: Bool?
            let files: FileInfo
        }

        let records: [AnnotationWithFile] = try await client
            .from("annotations")
            .select("*, files(name)")
            .order("created_at", ascending: false)
            .execute()
            .value

        // Supabase PostgreSQL timestamp formatını parse et
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return records.compactMap { record in
            guard let type = AnnotationType(rawValue: record.type) else { return nil }

            // Tarih parse - fallback için debug log
            let createdAt: Date
            if let parsedDate = dateFormatter.date(from: record.created_at) {
                createdAt = parsedDate
            } else {
                logError("SupabaseService", "Tarih parse hatası", error: NSError(domain: "DateParse", code: 0, userInfo: [NSLocalizedDescriptionKey: "created_at parse edilemedi: \(record.created_at)"]))
                createdAt = Date()
            }

            let annotation = Annotation(
                id: record.id,
                fileId: record.file_id.uuidString,  // UUID'yi String'e çevir
                pageNumber: record.page,
                type: type,
                color: record.data.color,
                rects: record.data.rects,
                text: record.data.text,
                note: record.data.note,
                isAiGenerated: record.data.isAiGenerated ?? false,
                createdAt: createdAt
            )
            return (annotation: annotation, fileName: record.files.name, isFavorite: record.is_favorite ?? false)
        }
    }

    // MARK: - Favorite Operations

    /// Annotation favori durumunu değiştir
    func toggleAnnotationFavorite(id: String, isFavorite: Bool) async throws {
        struct FavoriteUpdate: Encodable {
            let is_favorite: Bool
        }

        try await client
            .from("annotations")
            .update(FavoriteUpdate(is_favorite: isFavorite))
            .eq("id", value: id)
            .execute()

        logInfo("SupabaseService", "Annotation favori durumu güncellendi", details: "ID: \(id), Favori: \(isFavorite)")
    }

    /// Favori annotation'ları getir
    func getFavoriteAnnotations() async throws -> [(annotation: Annotation, fileName: String)] {
        struct AnnotationData: Decodable {
            let color: String
            let rects: [AnnotationRect]
            let text: String?
            let note: String?
            let isAiGenerated: Bool?
        }

        struct FileInfo: Decodable {
            let name: String
        }

        struct AnnotationWithFile: Decodable {
            let id: String
            let file_id: UUID
            let page: Int
            let type: String
            let data: AnnotationData
            let created_at: String
            let files: FileInfo
        }

        let records: [AnnotationWithFile] = try await client
            .from("annotations")
            .select("*, files(name)")
            .eq("is_favorite", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return records.compactMap { record in
            guard let type = AnnotationType(rawValue: record.type) else { return nil }

            let createdAt = dateFormatter.date(from: record.created_at) ?? Date()

            let annotation = Annotation(
                id: record.id,
                fileId: record.file_id.uuidString,
                pageNumber: record.page,
                type: type,
                color: record.data.color,
                rects: record.data.rects,
                text: record.data.text,
                note: record.data.note,
                isAiGenerated: record.data.isAiGenerated ?? false,
                createdAt: createdAt
            )
            return (annotation: annotation, fileName: record.files.name)
        }
    }

    /// Annotation istatistiklerini getir (Dashboard için)
    func getAnnotationStats() async throws -> (total: Int, highlights: Int, notes: Int, aiNotes: Int, favorites: Int, colorCounts: [String: Int]) {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı oturumu yok"])
        }

        struct AnnotationRecord: Decodable {
            let type: String
            let is_favorite: Bool?
            let data: AnnotationData

            struct AnnotationData: Decodable {
                let color: String
                let note: String?
                let isAiGenerated: Bool?
            }
        }

        let records: [AnnotationRecord] = try await client
            .from("annotations")
            .select("type, is_favorite, data")
            .eq("user_id", value: userId)
            .execute()
            .value

        var highlights = 0
        var notes = 0
        var aiNotes = 0
        var favorites = 0
        var colorCounts: [String: Int] = [:]

        for record in records {
            // Tip sayımı
            if record.type == "highlight" {
                highlights += 1
            }

            // Not sayımı (AI notları HARİÇ - sadece kullanıcı notları)
            let hasNote = record.data.note != nil && !record.data.note!.isEmpty
            let isAI = record.data.isAiGenerated == true

            if hasNote && !isAI {
                notes += 1
            }

            // AI not sayımı
            if isAI {
                aiNotes += 1
            }

            // Favori sayımı
            if record.is_favorite == true {
                favorites += 1
            }

            // Renk sayımı
            let color = record.data.color.lowercased()
            colorCounts[color, default: 0] += 1
        }

        return (
            total: records.count,
            highlights: highlights,
            notes: notes,
            aiNotes: aiNotes,
            favorites: favorites,
            colorCounts: colorCounts
        )
    }

    /// Dosya bazlı annotation sayılarını getir
    func getFileAnnotationCounts() async throws -> [(fileId: String, fileName: String, count: Int)] {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı oturumu yok"])
        }

        // Session'dan access token al
        guard let session = try? await client.auth.session else {
            logWarning("SupabaseService", "Session alınamadı - dosya annotation sayıları")
            return []
        }
        let accessToken = session.accessToken

        // RPC fonksiyonu kullan
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/get_file_annotation_counts"), resolvingAgainstBaseURL: false)!

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["p_user_id": userId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Fallback: basit sorgu
            return try await getFileAnnotationCountsFallback()
        }

        struct FileCount: Decodable {
            let file_id: String
            let file_name: String
            let annotation_count: Int
        }

        let results = try JSONDecoder().decode([FileCount].self, from: data)

        return results.map { ($0.file_id, $0.file_name, $0.annotation_count) }
    }

    private func getFileAnnotationCountsFallback() async throws -> [(fileId: String, fileName: String, count: Int)] {
        // Tüm annotation'ları al ve grupla
        let allAnnotations = try await getAllAnnotations()

        var fileCounts: [String: (name: String, count: Int)] = [:]

        for item in allAnnotations {
            let fileId = item.annotation.fileId
            if let existing = fileCounts[fileId] {
                fileCounts[fileId] = (existing.name, existing.count + 1)
            } else {
                fileCounts[fileId] = (item.fileName, 1)
            }
        }

        return fileCounts.map { (fileId: $0.key, fileName: $0.value.name, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    // MARK: - RAG Operations (Document Chunks)
    
    /// Chunk'ları ve embedding'leri Supabase'e kaydet
    func saveDocumentChunks(_ chunksWithEmbeddings: [(chunk: DocumentChunk, embedding: [Float])]) async throws {
        guard !chunksWithEmbeddings.isEmpty else { return }
        
        struct ChunkInsert: Encodable {
            let file_id: UUID
            let chunk_index: Int
            let content: String
            let page_number: Int?
            let embedding: String  // pgvector format: [0.1, 0.2, ...]
        }
        
        let inserts = chunksWithEmbeddings.map { item in
            // Embedding'i pgvector formatına çevir
            let embeddingString = "[" + item.embedding.map { String($0) }.joined(separator: ",") + "]"
            
            return ChunkInsert(
                file_id: item.chunk.fileId,
                chunk_index: item.chunk.chunkIndex,
                content: item.chunk.content,
                page_number: item.chunk.pageNumber,
                embedding: embeddingString
            )
        }
        
        // Batch insert
        try await client.from("document_chunks").insert(inserts).execute()
        
        logInfo("SupabaseService", "Chunk'lar kaydedildi", details: "\(inserts.count) adet")
    }
    
    /// Benzer chunk'ları vektör aramasıyla bul (benzerlik eşiği filtreli)
    func searchSimilarChunks(embedding: [Float], fileId: UUID, limit: Int = 16, similarityThreshold: Float = 0.25) async throws -> [DocumentChunk] {
        // Embedding'i pgvector formatına çevir
        let embeddingString = "[" + embedding.map { String($0) }.joined(separator: ",") + "]"
        
        logDebug("SupabaseService", "Vector arama başlatılıyor", 
                details: "FileID: \(fileId.uuidString), Embedding boyutu: \(embedding.count), Threshold: \(similarityThreshold)")
        
        // Doğrudan REST API ile RPC çağrısı yap (MainActor izolasyon sorununu bypass eder)
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/match_document_chunks_v2"), resolvingAgainstBaseURL: false)!
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "query_embedding": embeddingString,
            "match_file_id": fileId.uuidString.lowercased(),
            "match_count": limit,
            "similarity_threshold": similarityThreshold
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logWarning("SupabaseService", "RAG arama hatası", details: "Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            // Fallback: eski fonksiyonu dene
            return try await searchSimilarChunksLegacy(embedding: embedding, fileId: fileId, limit: limit)
        }
        
        let results = try JSONDecoder().decode([RAGSearchResult].self, from: data)
        
        // Client-side filtre (ek güvenlik)
        let filteredResults = results.filter { $0.similarity >= similarityThreshold }
        
        logInfo("SupabaseService", "RAG sonuçları filtrelendi", details: "\(filteredResults.count)/\(results.count) chunk eşiği geçti")
        
        return filteredResults.map { result in
            DocumentChunk(
                id: result.id,
                fileId: result.file_id,
                chunkIndex: result.chunk_index,
                content: result.content,
                pageNumber: result.page_number
            )
        }
    }
    
    /// Legacy benzerlik araması (eşiksiz, fallback için)
    private func searchSimilarChunksLegacy(embedding: [Float], fileId: UUID, limit: Int) async throws -> [DocumentChunk] {
        let embeddingString = "[" + embedding.map { String($0) }.joined(separator: ",") + "]"
        
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/match_document_chunks"), resolvingAgainstBaseURL: false)!
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "query_embedding": embeddingString,
            "match_file_id": fileId.uuidString.lowercased(),
            "match_count": limit
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return []
        }
        
        let results = try JSONDecoder().decode([RAGSearchResult].self, from: data)
        
        return results.map { result in
            DocumentChunk(
                id: result.id,
                fileId: result.file_id,
                chunkIndex: result.chunk_index,
                content: result.content,
                pageNumber: result.page_number
            )
        }
    }
    
    /// Dosya için chunk sayısını al
    func getChunkCount(fileId: UUID) async throws -> Int {
        struct ChunkRecord: Decodable {
            let id: UUID
        }
        
        let results: [ChunkRecord] = try await client
            .from("document_chunks")
            .select("id")
            .eq("file_id", value: fileId)
            .execute()
            .value
        
        return results.count
    }
    
    /// Dosya silindiğinde chunk'ları da sil
    func deleteDocumentChunks(fileId: UUID) async throws {
        try await client
            .from("document_chunks")
            .delete()
            .eq("file_id", value: fileId)
            .execute()
        
        logInfo("SupabaseService", "Chunk'lar silindi", details: "FileID: \(fileId)")
    }
    
    // MARK: - Faz 3: BM25 Full-Text Search
    
    /// BM25 (full-text search) ile chunk arama
    func searchChunksBM25(query: String, fileId: UUID, limit: Int = 8) async throws -> [DocumentChunk] {
        // Türkçe için basit tokenization - stopwords çıkar ve kelimeleri ayır
        let stopwords = ["ve", "veya", "ile", "için", "bu", "bir", "de", "da", "mı", "mi", "mu", "mü", "ki", "ama", "fakat", "ancak", "çünkü", "gibi", "kadar", "ne", "nasıl", "neden", "nerede"]
        
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopwords.contains($0) && $0.count > 2 }
        
        guard !words.isEmpty else {
            logDebug("SupabaseService", "BM25 arama: geçerli kelime bulunamadı")
            return []
        }
        
        // PostgreSQL tsquery formatı: kelime1 | kelime2 | kelime3 (OR)
        let tsQuery = words.joined(separator: " | ")
        
        logDebug("SupabaseService", "BM25 arama başlatılıyor", details: "Query: \(tsQuery)")
        
        // Session'dan access token al
        guard let session = try? await client.auth.session else {
            logWarning("SupabaseService", "Session alınamadı - BM25 arama")
            return []
        }
        let accessToken = session.accessToken
        
        // RPC fonksiyonunu çağır
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/search_chunks_bm25"), resolvingAgainstBaseURL: false)!
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "search_query": tsQuery,
            "target_file_id": fileId.uuidString.lowercased(),
            "match_count": limit
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            logWarning("SupabaseService", "BM25 arama başarısız", details: "Status: \(statusCode), Body: \(responseBody.prefix(200))")
            
            // Fallback: basit ILIKE arama
            return try await searchChunksSimple(query: query, fileId: fileId, limit: limit)
        }
        
        struct BM25Result: Decodable {
            let id: UUID
            let file_id: UUID
            let chunk_index: Int
            let content: String
            let page_number: Int?
            let rank: Float?
        }
        
        let results = try JSONDecoder().decode([BM25Result].self, from: data)
        
        logInfo("SupabaseService", "BM25 arama tamamlandı", details: "\(results.count) sonuç")
        
        return results.map { result in
            DocumentChunk(
                id: result.id,
                fileId: result.file_id,
                chunkIndex: result.chunk_index,
                content: result.content,
                pageNumber: result.page_number
            )
        }
    }
    
    /// Basit ILIKE arama (BM25 fallback)
    private func searchChunksSimple(query: String, fileId: UUID, limit: Int) async throws -> [DocumentChunk] {
        // Kelimeleri ayır
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
            .prefix(3) // İlk 3 kelimeyle sınırla
        
        guard !words.isEmpty else { return [] }
        
        struct ChunkRecord: Decodable {
            let id: UUID
            let file_id: UUID
            let chunk_index: Int
            let content: String
            let page_number: Int?
        }
        
        // İlk kelimeyle arama yap
        let searchPattern = "%\(words.first!)%"
        
        let results: [ChunkRecord] = try await client
            .from("document_chunks")
            .select()
            .eq("file_id", value: fileId)
            .ilike("content", pattern: searchPattern)
            .limit(limit)
            .execute()
            .value
        
        logDebug("SupabaseService", "Basit arama tamamlandı", details: "\(results.count) sonuç")
        
        return results.map { result in
            DocumentChunk(
                id: result.id,
                fileId: result.file_id,
                chunkIndex: result.chunk_index,
                content: result.content,
                pageNumber: result.page_number
            )
        }
    }
    
    // MARK: - PDF Image Metadata Operations
    
    /// Görsel metadata'larını toplu kaydet
    func saveImageMetadata(_ images: [PDFImageMetadata]) async throws {
        guard !images.isEmpty else { return }
        
        let inserts = images.map { image in
            PDFImageMetadata.InsertPayload(
                file_id: image.fileId,
                page_number: image.pageNumber,
                image_index: image.imageIndex,
                bounds: image.bounds,
                thumbnail_base64: image.thumbnailBase64
            )
        }
        
        try await client.from("pdf_images").insert(inserts).execute()
        
        logInfo("SupabaseService", "Görsel metadata kaydedildi", details: "\(inserts.count) adet")
    }
    
    /// Dosyadaki tüm görsel metadata'larını getir
    func getImageMetadata(fileId: UUID) async throws -> [PDFImageMetadata] {
        let records: [PDFImageMetadata.SupabaseRecord] = try await client
            .from("pdf_images")
            .select()
            .eq("file_id", value: fileId)
            .order("page_number")
            .order("image_index")
            .execute()
            .value
        
        return records.map { $0.toModel() }
    }
    
    /// Belirli bir sayfadaki görselleri getir
    func getPageImages(fileId: UUID, pageNumber: Int) async throws -> [PDFImageMetadata] {
        let records: [PDFImageMetadata.SupabaseRecord] = try await client
            .from("pdf_images")
            .select()
            .eq("file_id", value: fileId)
            .eq("page_number", value: pageNumber)
            .order("image_index")
            .execute()
            .value
        
        return records.map { $0.toModel() }
    }
    
    /// Görsel caption güncelle (lazy analiz sonrası)
    func updateImageCaption(imageId: UUID, caption: String, embedding: [Float]?) async throws {
        let dateFormatter = ISO8601DateFormatter()
        let embeddingString = embedding.map { "[" + $0.map { String($0) }.joined(separator: ",") + "]" }
        
        let updatePayload = PDFImageMetadata.CaptionUpdatePayload(
            caption: caption,
            caption_embedding: embeddingString,
            analyzed_at: dateFormatter.string(from: Date())
        )
        
        try await client
            .from("pdf_images")
            .update(updatePayload)
            .eq("id", value: imageId)
            .execute()
        
        logInfo("SupabaseService", "Görsel caption güncellendi", details: "ID: \(imageId)")
    }
    
    /// Analiz edilmemiş görselleri getir (batch analiz için)
    func getUnanalyzedImages(fileId: UUID, limit: Int = 5) async throws -> [PDFImageMetadata] {
        let records: [PDFImageMetadata.SupabaseRecord] = try await client
            .from("pdf_images")
            .select()
            .eq("file_id", value: fileId)
            .is("analyzed_at", value: nil)
            .order("page_number")
            .limit(limit)
            .execute()
            .value
        
        return records.map { $0.toModel() }
    }
    
    /// Görsel caption'larında arama (RAG hibrit arama için)
    func searchImageCaptions(embedding: [Float], fileId: UUID, limit: Int = 3, threshold: Float = 0.6) async throws -> [PDFImageMetadata] {
        let embeddingString = "[" + embedding.map { String($0) }.joined(separator: ",") + "]"
        
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/search_image_captions"), resolvingAgainstBaseURL: false)!
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "query_embedding": embeddingString,
            "target_file_id": fileId.uuidString.lowercased(),
            "match_count": limit,
            "similarity_threshold": threshold
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logWarning("SupabaseService", "Görsel caption araması başarısız")
            return []
        }
        
        struct CaptionSearchResult: Decodable {
            let id: UUID
            let page_number: Int
            let caption: String
            let similarity: Float
        }
        
        let results = try JSONDecoder().decode([CaptionSearchResult].self, from: data)
        
        // Basit PDFImageMetadata döndür (sadece arama sonucu için gerekli alanlar)
        return results.map { result in
            PDFImageMetadata(
                id: result.id,
                fileId: fileId,
                pageNumber: result.page_number,
                caption: result.caption
            )
        }
    }
    
    /// Dosyadaki görsel sayısını getir
    func getImageCount(fileId: UUID) async throws -> Int {
        struct CountResult: Decodable {
            let id: UUID
        }
        
        let results: [CountResult] = try await client
            .from("pdf_images")
            .select("id")
            .eq("file_id", value: fileId)
            .execute()
            .value
        
        return results.count
    }
    
    /// Dosya silindiğinde görsel metadata'larını da sil
    func deleteImageMetadata(fileId: UUID) async throws {
        try await client
            .from("pdf_images")
            .delete()
            .eq("file_id", value: fileId)
            .execute()
        
        logInfo("SupabaseService", "Görsel metadata silindi", details: "FileID: \(fileId)")
    }
    
    // MARK: - Folder Operations
    
    /// Klasör oluştur
    func createFolder(name: String, color: String = "#6366F1", parentId: UUID? = nil) async throws -> Folder {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı oturumu yok"])
        }
        
        struct FolderInsert: Encodable {
            let user_id: String
            let name: String
            let color: String
            let parent_id: UUID?
        }
        
        struct FolderResponse: Decodable {
            let id: UUID
            let name: String
            let color: String
            let parent_id: UUID?
            let created_at: String
        }
        
        let response: FolderResponse = try await client
            .from("folders")
            .insert(FolderInsert(user_id: userId, name: name, color: color, parent_id: parentId))
            .select()
            .single()
            .execute()
            .value
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        logInfo("SupabaseService", "Klasör oluşturuldu", details: name)
        
        return Folder(
            id: response.id,
            name: response.name,
            color: response.color,
            parentId: response.parent_id,
            userId: userId,
            createdAt: dateFormatter.date(from: response.created_at) ?? Date(),
            fileCount: 0
        )
    }
    
    /// Kullanıcının klasörlerini listele
    func listFolders(parentId: UUID? = nil) async throws -> [Folder] {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı oturumu yok"])
        }
        
        // Session'dan access token al
        guard let session = try? await client.auth.session else {
            logWarning("SupabaseService", "Session alınamadı - klasör listesi")
            return []
        }
        let accessToken = session.accessToken
        
        // RPC fonksiyonunu kullan (dosya sayısıyla birlikte)
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/get_folders_with_count"), resolvingAgainstBaseURL: false)!
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        var body: [String: Any] = ["p_user_id": userId]
        if let parentId = parentId {
            body["p_parent_id"] = parentId.uuidString.lowercased()
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            logWarning("SupabaseService", "Klasör listesi alınamadı", details: "Status: \(statusCode), Body: \(responseBody)")
            return []
        }
        
        struct FolderResult: Decodable {
            let id: UUID
            let name: String
            let color: String
            let parent_id: UUID?
            let created_at: String
            let file_count: Int
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let results = try JSONDecoder().decode([FolderResult].self, from: data)
        
        logInfo("SupabaseService", "Klasörler yüklendi", details: "\(results.count) klasör bulundu")
        
        return results.map { result in
            Folder(
                id: result.id,
                name: result.name,
                color: result.color,
                parentId: result.parent_id,
                userId: userId,
                createdAt: dateFormatter.date(from: result.created_at) ?? Date(),
                fileCount: result.file_count
            )
        }
    }
    
    /// Klasör sil
    func deleteFolder(id: UUID) async throws {
        try await client
            .from("folders")
            .delete()
            .eq("id", value: id)
            .execute()
        
        logInfo("SupabaseService", "Klasör silindi", details: "ID: \(id)")
    }
    
    /// Dosyayı klasöre taşı
    func moveFileToFolder(fileId: String, folderId: UUID?) async throws {
        struct FolderUpdate: Encodable {
            let folder_id: UUID?
        }
        
        try await client
            .from("files")
            .update(FolderUpdate(folder_id: folderId))
            .eq("id", value: fileId)
            .execute()
        
        logInfo("SupabaseService", "Dosya taşındı", details: "File: \(fileId) -> Folder: \(folderId?.uuidString ?? "Ana Klasör")")
    }
    
    // MARK: - Tag Operations
    
    /// Etiket oluştur veya mevcut olanı getir
    func getOrCreateTag(name: String, color: String? = nil, isAutoGenerated: Bool = true) async throws -> Tag {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı oturumu yok"])
        }
        
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Önce mevcut etiketi ara
        struct TagRecord: Decodable {
            let id: UUID
            let name: String
            let color: String
            let is_auto_generated: Bool
            let created_at: String
        }
        
        let existing: [TagRecord] = try await client
            .from("tags")
            .select()
            .eq("user_id", value: userId)
            .ilike("name", pattern: normalizedName)
            .execute()
            .value
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let existingTag = existing.first {
            return Tag(
                id: existingTag.id,
                name: existingTag.name,
                color: existingTag.color,
                userId: userId,
                createdAt: dateFormatter.date(from: existingTag.created_at) ?? Date(),
                fileCount: 0,
                isAutoGenerated: existingTag.is_auto_generated
            )
        }
        
        // Yoksa oluştur
        struct TagInsert: Encodable {
            let user_id: String
            let name: String
            let color: String
            let is_auto_generated: Bool
        }
        
        let colors = ["#22C55E", "#3B82F6", "#8B5CF6", "#F59E0B", "#EF4444", "#EC4899", "#14B8A6", "#6366F1"]
        let randomColor = color ?? colors.randomElement() ?? "#22C55E"
        
        let response: TagRecord = try await client
            .from("tags")
            .insert(TagInsert(user_id: userId, name: normalizedName, color: randomColor, is_auto_generated: isAutoGenerated))
            .select()
            .single()
            .execute()
            .value
        
        logInfo("SupabaseService", "Etiket oluşturuldu", details: normalizedName)
        
        return Tag(
            id: response.id,
            name: response.name,
            color: response.color,
            userId: userId,
            createdAt: dateFormatter.date(from: response.created_at) ?? Date(),
            fileCount: 0,
            isAutoGenerated: response.is_auto_generated
        )
    }
    
    /// Dosyaya etiketler ekle
    func addTagsToFile(fileId: String, tagIds: [UUID]) async throws {
        guard !tagIds.isEmpty else { return }
        
        struct FileTagInsert: Encodable {
            let file_id: String
            let tag_id: UUID
        }
        
        let inserts = tagIds.map { FileTagInsert(file_id: fileId, tag_id: $0) }
        
        // Upsert benzeri davranış için conflict'i yoksay
        try await client
            .from("file_tags")
            .upsert(inserts, onConflict: "file_id,tag_id")
            .execute()
        
        logInfo("SupabaseService", "Etiketler dosyaya eklendi", details: "\(tagIds.count) etiket")
    }
    
    /// Dosyanın etiketlerini getir
    func getFileTags(fileId: String) async throws -> [Tag] {
        guard let userId = currentUser?.id else { return [] }
        
        struct FileTagRecord: Decodable {
            let tag_id: UUID
            let tags: TagInfo
            
            struct TagInfo: Decodable {
                let id: UUID
                let name: String
                let color: String
                let is_auto_generated: Bool
                let created_at: String
            }
        }
        
        let records: [FileTagRecord] = try await client
            .from("file_tags")
            .select("tag_id, tags(*)")
            .eq("file_id", value: fileId)
            .execute()
            .value
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return records.map { record in
            Tag(
                id: record.tags.id,
                name: record.tags.name,
                color: record.tags.color,
                userId: userId,
                createdAt: dateFormatter.date(from: record.tags.created_at) ?? Date(),
                fileCount: 0,
                isAutoGenerated: record.tags.is_auto_generated
            )
        }
    }
    
    /// Kullanıcının tüm etiketlerini listele (dosya sayısıyla)
    func listTags() async throws -> [Tag] {
        guard let userId = currentUser?.id else { return [] }
        
        // Session'dan access token al
        guard let session = try? await client.auth.session else {
            logWarning("SupabaseService", "Session alınamadı - etiket listesi")
            return []
        }
        let accessToken = session.accessToken
        
        // RPC fonksiyonunu kullan
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/get_tags_with_count"), resolvingAgainstBaseURL: false)!
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["p_user_id": userId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            logWarning("SupabaseService", "Etiket listesi alınamadı", details: "Status: \(statusCode), Body: \(responseBody)")
            return []
        }
        
        struct TagResult: Decodable {
            let id: UUID
            let name: String
            let color: String
            let is_auto_generated: Bool
            let created_at: String
            let file_count: Int
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let results = try JSONDecoder().decode([TagResult].self, from: data)
        
        logInfo("SupabaseService", "Etiketler yüklendi", details: "\(results.count) etiket bulundu")
        
        return results.map { result in
            Tag(
                id: result.id,
                name: result.name,
                color: result.color,
                userId: userId,
                createdAt: dateFormatter.date(from: result.created_at) ?? Date(),
                fileCount: result.file_count,
                isAutoGenerated: result.is_auto_generated
            )
        }
    }
    
    /// Etikete göre dosyaları filtrele
    func getFilesByTag(tagId: UUID) async throws -> [String] {
        struct FileTagRecord: Decodable {
            let file_id: String
        }
        
        let records: [FileTagRecord] = try await client
            .from("file_tags")
            .select("file_id")
            .eq("tag_id", value: tagId)
            .execute()
            .value
        
        return records.map { $0.file_id }
    }
    
    /// Dosyanın kategorisini güncelle
    func updateFileCategory(fileId: String, category: String) async throws {
        struct CategoryUpdate: Encodable {
            let ai_category: String
        }
        
        try await client
            .from("files")
            .update(CategoryUpdate(ai_category: category))
            .eq("id", value: fileId)
            .execute()
        
        logInfo("SupabaseService", "Dosya kategorisi güncellendi", details: "\(fileId): \(category)")
    }
    
    /// Kullanılmayan etiketleri temizle (hiç dosyası olmayan etiketleri sil)
    func cleanupUnusedTags() async throws {
        guard let userId = currentUser?.id else { return }
        
        // Session'dan access token al
        guard let session = try? await client.auth.session else {
            logWarning("SupabaseService", "Session alınamadı - etiket temizleme")
            return
        }
        let accessToken = session.accessToken
        
        // Önce tüm etiketleri dosya sayısıyla birlikte al
        let urlComponents = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/get_tags_with_count"), resolvingAgainstBaseURL: false)!
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["p_user_id": userId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logWarning("SupabaseService", "Etiket listesi alınamadı - temizleme için")
            return
        }
        
        struct TagResult: Decodable {
            let id: UUID
            let name: String
            let file_count: Int
        }
        
        let tags = try JSONDecoder().decode([TagResult].self, from: data)
        
        // Dosya sayısı 0 olan etiketleri sil
        let unusedTags = tags.filter { $0.file_count == 0 }
        
        for tag in unusedTags {
            try await client
                .from("tags")
                .delete()
                .eq("id", value: tag.id)
                .execute()
            
            logInfo("SupabaseService", "Kullanılmayan etiket silindi", details: tag.name)
        }
        
        if !unusedTags.isEmpty {
            logInfo("SupabaseService", "Etiket temizliği tamamlandı", details: "\(unusedTags.count) etiket silindi")
        }
    }
}

// MARK: - JSON Value Extension
extension Supabase.AnyJSON {
    var stringValue: String? {
        switch self {
        case .string(let str):
            return str
        default:
            return nil
        }
    }
}
