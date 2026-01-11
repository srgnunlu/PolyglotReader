import Foundation
import Combine
import SwiftUI

// MARK: - Settings ViewModel
@MainActor
class SettingsViewModel: ObservableObject {
    @Published var preferences: UserPreferences {
        didSet {
            savePreferences()
        }
    }

    private let preferencesKey = "polyglot_preferences"

    var colorScheme: ColorScheme? {
        switch preferences.theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: preferencesKey),
           let savedPrefs = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            self.preferences = savedPrefs
        } else {
            self.preferences = UserPreferences()
        }
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
    }

    func setTheme(_ theme: UserPreferences.ThemeMode) {
        preferences.theme = theme
    }

    func toggleAutoSummary() {
        preferences.autoSummary.toggle()
    }

    func toggleNotifications() {
        preferences.enableNotifications.toggle()
    }

    func setLanguage(_ language: String) {
        preferences.defaultLanguage = language
    }
}
