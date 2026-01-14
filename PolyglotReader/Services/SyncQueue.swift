import Foundation
import Combine

// MARK: - Operation Type
/// Types of operations that can be queued for later sync
enum SyncOperationType: String, Codable {
    case annotationCreate = "annotation_create"
    case annotationUpdate = "annotation_update"
    case annotationDelete = "annotation_delete"
    case chatMessage = "chat_message"
    case fileUpload = "file_upload"
    case readingProgress = "reading_progress"
}

// MARK: - Pending Operation
/// Represents an operation that couldn't be completed due to network issues
struct PendingOperation: Codable, Identifiable {
    let id: UUID
    let type: SyncOperationType
    let payload: Data
    let fileId: String?
    let createdAt: Date
    var retryCount: Int
    var lastRetryAt: Date?

    init(
        id: UUID = UUID(),
        type: SyncOperationType,
        payload: Data,
        fileId: String? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastRetryAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.fileId = fileId
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
    }
}

// MARK: - Sync Status
/// Current status of the sync queue
enum SyncStatus: Equatable {
    case idle
    case syncing(progress: Float)
    case error(message: String)
    case completed
}

// MARK: - Sync Queue
/// Manages pending operations for offline-to-online sync
@MainActor
final class SyncQueue: ObservableObject {
    static let shared = SyncQueue()

    // MARK: - Published Properties

    /// Current sync status
    @Published private(set) var status: SyncStatus = .idle

    /// Number of pending operations
    @Published private(set) var pendingCount: Int = 0

    /// Whether there are pending operations
    var hasPendingOperations: Bool { pendingCount > 0 }

    // MARK: - Private Properties

    private let storageKey = "polyglotreader.sync_queue"
    private let maxRetries = 3
    private var pendingOperations: [PendingOperation] = []
    private var cancellables = Set<AnyCancellable>()
    private var syncTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        loadFromStorage()
        setupNetworkObserver()

        #if DEBUG
        MemoryDebugger.shared.logInit(self)
        #endif
    }

    deinit {
        syncTask?.cancel()
        cancellables.removeAll()
        #if DEBUG
        Task { @MainActor in
            MemoryDebugger.shared.logDeinit(self)
        }
        #endif
    }

    // MARK: - Network Observer

    private func setupNetworkObserver() {
        NotificationCenter.default.publisher(for: NetworkMonitor.networkDidBecomeAvailable)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.processQueue()
            }
            .store(in: &cancellables)
    }

    // MARK: - Queue Management

    /// Enqueue an operation for later sync
    /// - Parameters:
    ///   - type: The type of operation
    ///   - payload: The encoded payload data
    ///   - fileId: Optional file ID for context
    func enqueue(type: SyncOperationType, payload: Data, fileId: String? = nil) {
        let operation = PendingOperation(
            type: type,
            payload: payload,
            fileId: fileId
        )

        pendingOperations.append(operation)
        pendingCount = pendingOperations.count
        saveToStorage()

        logInfo("SyncQueue", "Operation queued", details: "\(type.rawValue) - Total pending: \(pendingCount)")
    }

    /// Enqueue an encodable object for later sync
    /// - Parameters:
    ///   - type: The type of operation
    ///   - object: The encodable object
    ///   - fileId: Optional file ID for context
    func enqueue<T: Encodable>(type: SyncOperationType, object: T, fileId: String? = nil) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(object)
        enqueue(type: type, payload: payload, fileId: fileId)
    }

    /// Process all pending operations
    func processQueue() {
        guard !pendingOperations.isEmpty else {
            status = .idle
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            logDebug("SyncQueue", "Cannot process queue - offline")
            return
        }

        // Cancel any existing sync task
        syncTask?.cancel()

        syncTask = Task { [weak self] in
            await self?.processQueueAsync()
        }
    }

    private func processQueueAsync() async {
        status = .syncing(progress: 0)
        logInfo("SyncQueue", "Processing sync queue", details: "\(pendingOperations.count) operations")

        var successfulOperations: [UUID] = []
        var failedOperations: [UUID] = []
        let totalOperations = Float(pendingOperations.count)

        for (index, operation) in pendingOperations.enumerated() {
            guard !Task.isCancelled else { break }

            // Update progress
            status = .syncing(progress: Float(index) / totalOperations)

            do {
                try await processOperation(operation)
                successfulOperations.append(operation.id)
                logDebug("SyncQueue", "Operation synced", details: operation.type.rawValue)
            } catch {
                logWarning("SyncQueue", "Operation failed", details: error.localizedDescription)

                // Update retry count
                if var op = pendingOperations.first(where: { $0.id == operation.id }) {
                    op.retryCount += 1
                    op.lastRetryAt = Date()

                    if op.retryCount >= maxRetries {
                        failedOperations.append(operation.id)
                        logWarning("SyncQueue", "Max retries reached for operation", details: operation.type.rawValue)
                    }
                }
            }
        }

        // Remove successful and max-retried operations
        pendingOperations.removeAll { operation in
            successfulOperations.contains(operation.id) || failedOperations.contains(operation.id)
        }

        pendingCount = pendingOperations.count
        saveToStorage()

        // Update final status
        if !failedOperations.isEmpty {
            status = .error(message: "\(failedOperations.count) işlem senkronize edilemedi")
        } else if pendingOperations.isEmpty {
            status = .completed
            logInfo("SyncQueue", "Queue processing completed ✅")

            // Reset to idle after short delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            status = .idle
        } else {
            status = .idle
        }
    }

    private func processOperation(_ operation: PendingOperation) async throws {
        switch operation.type {
        case .annotationCreate:
            try await processAnnotationCreate(operation)
        case .annotationUpdate:
            try await processAnnotationUpdate(operation)
        case .annotationDelete:
            try await processAnnotationDelete(operation)
        case .chatMessage:
            try await processChatMessage(operation)
        case .fileUpload:
            // File upload requires special handling - not implemented in queue
            throw SyncError.notSupported
        case .readingProgress:
            try await processReadingProgress(operation)
        }
    }

    // MARK: - Operation Processors

    private func processAnnotationCreate(_ operation: PendingOperation) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let annotation = try decoder.decode(Annotation.self, from: operation.payload)
        try await SupabaseService.shared.saveAnnotation(annotation)
    }

    private func processAnnotationUpdate(_ operation: PendingOperation) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let annotation = try decoder.decode(Annotation.self, from: operation.payload)
        try await SupabaseService.shared.updateAnnotation(
            id: annotation.id,
            note: annotation.note,
            color: annotation.color
        )
    }

    private func processAnnotationDelete(_ operation: PendingOperation) async throws {
        guard let annotationId = String(data: operation.payload, encoding: .utf8) else {
            throw SyncError.invalidPayload
        }
        try await SupabaseService.shared.deleteAnnotation(id: annotationId)
    }

    private func processChatMessage(_ operation: PendingOperation) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(ChatMessage.self, from: operation.payload)
        guard let fileId = operation.fileId else {
            throw SyncError.missingFileId
        }
        try await SupabaseService.shared.saveChatMessage(
            fileId: fileId,
            role: message.role.rawValue,
            content: message.text
        )
    }

    private func processReadingProgress(_ operation: PendingOperation) async throws {
        guard let fileId = operation.fileId else {
            throw SyncError.missingFileId
        }

        let decoder = JSONDecoder()
        let progressData = try decoder.decode(ReadingProgressPayload.self, from: operation.payload)

        try await SupabaseService.shared.saveReadingProgress(
            fileId: fileId,
            page: progressData.page,
            offsetX: progressData.offsetX,
            offsetY: progressData.offsetY,
            scale: progressData.scale
        )
    }

    // MARK: - Persistence

    private func saveToStorage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(pendingOperations)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logError("SyncQueue", "Failed to save queue", error: error)
        }
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            pendingOperations = try decoder.decode([PendingOperation].self, from: data)
            pendingCount = pendingOperations.count
            logInfo("SyncQueue", "Loaded queue from storage", details: "\(pendingCount) pending operations")
        } catch {
            logError("SyncQueue", "Failed to load queue", error: error)
            pendingOperations = []
        }
    }

    /// Clear all pending operations (use with caution)
    func clearQueue() {
        pendingOperations.removeAll()
        pendingCount = 0
        saveToStorage()
        status = .idle
        logWarning("SyncQueue", "Queue cleared")
    }

    /// Get operations for a specific file
    func getOperations(forFileId fileId: String) -> [PendingOperation] {
        pendingOperations.filter { $0.fileId == fileId }
    }
}

// MARK: - Supporting Types

private struct ReadingProgressPayload: Codable {
    let page: Int
    let offsetX: Double
    let offsetY: Double
    let scale: Double
}

enum SyncError: Error, LocalizedError {
    case invalidPayload
    case missingFileId
    case notSupported

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Geçersiz veri formatı"
        case .missingFileId:
            return "Dosya ID'si eksik"
        case .notSupported:
            return "Bu işlem senkronizasyon kuyruğunda desteklenmiyor"
        }
    }
}
