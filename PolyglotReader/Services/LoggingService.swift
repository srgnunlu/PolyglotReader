import Foundation
import Combine
import os.log

// MARK: - Log Level
enum LogLevel: String, CaseIterable, Codable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🛑"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

// MARK: - Log Entry
struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let source: String
    let message: String
    let details: String?

    init(level: LogLevel, source: String, message: String, details: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.source = source
        self.message = message
        self.details = details
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var displayText: String {
        var text = "[\(formattedTimestamp)] \(level.emoji) [\(source)] \(message)"
        if let details = details {
            text += "\n   └─ \(details)"
        }
        return text
    }
}

// MARK: - Log Settings
private let isDebugLoggingEnabled: Bool = {
    #if DEBUG
    return true
    #else
    return false
    #endif
}()

// MARK: - Sensitive Data Masking
private enum SensitiveDataMasker {
    private static let queryTokenRegex = makeRegex(
        "(?i)([?&#](access_token|refresh_token|id_token|token|apikey|api_key|key)=)([^&\\s]+)"
    )
    private static let bearerRegex = makeRegex("(?i)\\bBearer\\s+([A-Za-z0-9\\-._~+/]+=*)")
    private static let jwtRegex = makeRegex("\\beyJ[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+\\b")
    private static let jsonTokenRegex = makeRegex(
        "(?i)\"(access_token|refresh_token|provider_token|id_token|token|apikey|api_key)\"\\s*:\\s*\"[^\"]+\""
    )
    private static let emailRegex = makeRegex(
        "(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b"
    )

    static func mask(_ input: String) -> String {
        var output = input
        if let regex = queryTokenRegex {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "$1<redacted>"
            )
        }
        if let regex = bearerRegex {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "Bearer <redacted>"
            )
        }
        if let regex = jwtRegex {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "<redacted.jwt>"
            )
        }
        if let regex = jsonTokenRegex {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "\"$1\":\"<redacted>\""
            )
        }
        if let regex = emailRegex {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "<redacted.email>"
            )
        }
        return output
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [])
    }
}

// MARK: - Log Details Formatting
private enum LogDetailsFormatter {
    private static let embeddingRegex = makeRegex(
        "(?i)\"(query_embedding|embedding|caption_embedding)\"\\s*:\\s*\\[[\\s\\S]*?\\]"
    )
    private static let base64Regex = makeRegex(
        "(?i)\"(thumbnail_base64|base64)\"\\s*:\\s*\"[^\"]+\""
    )
    private static let isoTimestampRegex = makeRegex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}")

    static func format(_ input: String, level: LogLevel) -> String {
        var output = stripSupabasePrefix(input)
        output = redactLargePayloads(output)
        output = compactBody(output, level: level)
        output = truncate(output, maxLength: maxDetailsLength(for: level))
        return output
    }

    private static func stripSupabasePrefix(_ input: String) -> String {
        guard let range = input.range(of: "Request:") ?? input.range(of: "Response:") else {
            return input
        }
        let prefix = input[..<range.lowerBound]
        if prefix.contains("LoggerInterceptor") || containsIsoTimestamp(String(prefix)) {
            return String(input[range.lowerBound...])
        }
        return input
    }

    private static func redactLargePayloads(_ input: String) -> String {
        var output = input
        if let regex = embeddingRegex {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "\"$1\": [<redacted.embedding>]"
            )
        }
        if let regex = base64Regex {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "\"$1\":\"<redacted.base64>\""
            )
        }
        return output
    }

    private static func compactBody(_ input: String, level: LogLevel) -> String {
        guard let bodyRange = input.range(of: "Body:") else { return input }

        let afterBodyStart = input[bodyRange.upperBound...]
        let contextRange = afterBodyStart.range(of: "\ncontext:")
        let bodyContent = contextRange.map { afterBodyStart[..<$0.lowerBound] } ?? afterBodyStart
        let tail = contextRange.map { String(afterBodyStart[$0.lowerBound...]) } ?? ""

        let maxBodyLength = maxBodyLength(for: level)
        if bodyContent.count <= maxBodyLength {
            return input
        }

        let trimmed = bodyContent.prefix(maxBodyLength)
        let omittedCount = bodyContent.count - maxBodyLength
        return "\(input[..<bodyRange.upperBound]) \(trimmed)... <truncated \(omittedCount) chars>\(tail)"
    }

    private static func truncate(_ input: String, maxLength: Int) -> String {
        guard input.count > maxLength else { return input }
        let prefix = input.prefix(maxLength)
        let omitted = input.count - maxLength
        return "\(prefix)... <truncated \(omitted) chars>"
    }

    private static func maxBodyLength(for level: LogLevel) -> Int {
        switch level {
        case .debug: return 200
        case .info: return 300
        case .warning: return 1000
        case .error, .critical: return 2000
        }
    }

    private static func maxDetailsLength(for level: LogLevel) -> Int {
        switch level {
        case .debug: return 400
        case .info: return 600
        case .warning: return 1500
        case .error, .critical: return 3000
        }
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private static func containsIsoTimestamp(_ input: String) -> Bool {
        guard let regex = isoTimestampRegex else { return false }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, options: [], range: range) != nil
    }
}

// MARK: - Logging Service
@MainActor
final class LoggingService: ObservableObject {
    static let shared = LoggingService()

    @Published private(set) var logs: [LogEntry] = []

    private let maxLogCount = 500
    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "PolyglotReader", category: "App")
    private let logFileURL: URL?

    private init() {
        // Log dosyası yolu
        if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.logFileURL = documentsDir.appendingPathComponent("app_logs.txt")
        } else {
            self.logFileURL = nil
        }

        // Başlangıç logu
        log(.info, source: "LoggingService", message: "Loglama servisi başlatıldı")
    }

    // MARK: - Public Logging Methods

    func debug(_ source: String, _ message: String, details: String? = nil) {
        log(.debug, source: source, message: message, details: details)
    }

    func info(_ source: String, _ message: String, details: String? = nil) {
        log(.info, source: source, message: message, details: details)
    }

    func warning(_ source: String, _ message: String, details: String? = nil) {
        log(.warning, source: source, message: message, details: details)
    }

    func error(_ source: String, _ message: String, error: Error? = nil) {
        let details = error?.localizedDescription
        log(.error, source: source, message: message, details: details)
    }

    func critical(_ source: String, _ message: String, error: Error? = nil) {
        let details = error?.localizedDescription
        log(.critical, source: source, message: message, details: details)
    }

    // MARK: - Core Logging

    private func log(_ level: LogLevel, source: String, message: String, details: String? = nil) {
        if level == .debug && !isDebugLoggingEnabled {
            return
        }
        let sanitizedMessage = SensitiveDataMasker.mask(message)
        let sanitizedDetails = details
            .map { SensitiveDataMasker.mask($0) }
            .map { LogDetailsFormatter.format($0, level: level) }
        let entry = LogEntry(
            level: level,
            source: source,
            message: sanitizedMessage,
            details: sanitizedDetails
        )

        // Memory'e ekle
        logs.append(entry)

        // Max log sayısını kontrol et
        if logs.count > maxLogCount {
            logs.removeFirst(logs.count - maxLogCount)
        }

        // OS Log'a yaz
        os_log("%{public}@", log: osLog, type: level.osLogType, entry.displayText)

        // Dosyaya yaz (sadece warning ve üstü)
        if level == .warning || level == .error || level == .critical {
            writeToFile(entry)
        }
    }

    // MARK: - File Operations

    private func writeToFile(_ entry: LogEntry) {
        guard let url = logFileURL else { return }

        let line = "\(entry.displayText)\n"

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Public Utilities

    func clearLogs() {
        logs.removeAll()

        if let url = logFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        log(.info, source: "LoggingService", message: "Loglar temizlendi")
    }

    func filteredLogs(level: LogLevel? = nil, source: String? = nil) -> [LogEntry] {
        var filtered = logs

        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }

        if let source = source, !source.isEmpty {
            filtered = filtered.filter { $0.source.lowercased().contains(source.lowercased()) }
        }

        return filtered
    }

    func exportLogsAsText() -> String {
        logs.map { $0.displayText }.joined(separator: "\n")
    }

    func getLogFileURL() -> URL? {
        logFileURL
    }

    // MARK: - Stats

    var errorCount: Int {
        logs.filter { $0.level == .error || $0.level == .critical }.count
    }

    var warningCount: Int {
        logs.filter { $0.level == .warning }.count
    }
}

// MARK: - Global Convenience Functions
let Logger = LoggingService.shared

nonisolated func logDebug(_ source: String, _ message: String, details: String? = nil) {
    if !isDebugLoggingEnabled { return }
    Task { @MainActor in
        Logger.debug(source, message, details: details)
    }
}

nonisolated func logInfo(_ source: String, _ message: String, details: String? = nil) {
    Task { @MainActor in
        Logger.info(source, message, details: details)
    }
}

nonisolated func logWarning(_ source: String, _ message: String, details: String? = nil) {
    Task { @MainActor in
        Logger.warning(source, message, details: details)
    }
}

nonisolated func logError(_ source: String, _ message: String, error: Error? = nil) {
    Task { @MainActor in
        Logger.error(source, message, error: error)
    }
}

nonisolated func logCritical(_ source: String, _ message: String, error: Error? = nil) {
    Task { @MainActor in
        Logger.critical(source, message, error: error)
    }
}
