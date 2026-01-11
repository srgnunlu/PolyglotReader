import Foundation

extension ErrorHandlingService {
    func recordStateForError(_ appError: AppError) {
        stateSnapshot.lastErrorSignature = appError.signature
        stateSnapshot.lastErrorMessage = appError.errorDescription
        stateSnapshot.timestamp = Date()
        persistState(stateSnapshot)
    }

    func persistState(_ snapshot: AppStateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.setValue(data, forKey: stateStorageKey)
    }

    func loadPersistedState() -> AppStateSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: stateStorageKey) else { return nil }
        return try? JSONDecoder().decode(AppStateSnapshot.self, from: data)
    }
}
