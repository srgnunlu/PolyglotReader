import Foundation
import Combine
import Supabase

// MARK: - Supabase Service Facade

/// Main Supabase service providing unified access to all sub-services
/// Maintains backward compatibility with SupabaseService.shared usage
@MainActor
final class SupabaseService: ObservableObject {
    // MARK: - Singleton

    static let shared = SupabaseService()

    // MARK: - Sub-Services

    let auth: SupabaseAuthService
    let storage: SupabaseStorageService
    let files: SupabaseFileService
    let database: SupabaseDatabaseService
    let annotations: SupabaseAnnotationService

    // MARK: - Published Properties (for backward compatibility)

    @Published var currentUser: User?

    @Published var isLoading: Bool = false

    // Forward auth user binding
    private var cancellables = Set<AnyCancellable>()

    enum OperationCategory {
        case auth
        case storage
        case database
        case general
    }

    // MARK: - Legacy Access

    /// Legacy client access for gradual migration
    var client: SupabaseClient {
        SupabaseConfig.client
    }

    // MARK: - Initialization

    private init() {
        SecurityManager.shared.configure()
        let client = SupabaseConfig.client
        SecurityManager.shared.registerSupabaseClient(client)

        self.auth = SupabaseAuthService(client: client)
        self.storage = SupabaseStorageService(client: client)
        self.files = SupabaseFileService(client: client)
        self.database = SupabaseDatabaseService(client: client)
        self.annotations = SupabaseAnnotationService(client: client)

        // Bind auth state
        auth.$currentUser
            .sink { [weak self] user in
                self?.currentUser = user
            }
            .store(in: &cancellables)

        auth.$isLoading
            .sink { [weak self] loading in
                self?.isLoading = loading
            }
            .store(in: &cancellables)
    }

    // MARK: - Error Helpers

    func perform<T>(
        category: OperationCategory,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw mapError(error, category: category)
        }
    }

    func mapError(_ error: Error, category: OperationCategory) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if let supabaseError = error as? SupabaseError {
            return ErrorHandlingService.mapToAppError(supabaseError)
        }

        if let urlError = error as? URLError {
            return ErrorHandlingService.mapToAppError(urlError)
        }

        switch category {
        case .auth:
            return .authentication(reason: .invalidCredentials, underlying: error)
        case .storage:
            return .storage(reason: .writeFailed, underlying: error)
        case .database:
            return .storage(reason: .readFailed, underlying: error)
        case .general:
            return .unknown(
                message: NSLocalizedString("error.unknown", comment: ""),
                recoverySuggestion: NSLocalizedString("recovery.general.retry", comment: ""),
                underlying: error
            )
        }
    }

    func authenticationRequiredError() -> AppError {
        .authentication(reason: .required, underlying: SupabaseError.authenticationRequired)
    }

    // MARK: - Reading Progress

    func getReadingProgress(fileId: String) async throws -> ReadingProgress? {
        guard let userId = currentUser?.id else {
            return nil
        }

        return try await perform(category: .database) {
            try await self.database.getReadingProgress(fileId: fileId, userId: userId)
        }
    }

    func saveReadingProgress(fileId: String, page: Int, offsetX: Double, offsetY: Double, scale: Double) async throws {
        guard let userId = currentUser?.id else {
            return
        }

        try await perform(category: .database) {
            try await self.database.saveReadingProgress(
                fileId: fileId,
                userId: userId,
                page: page,
                offsetX: offsetX,
                offsetY: offsetY,
                scale: scale
            )
        }
    }
}
