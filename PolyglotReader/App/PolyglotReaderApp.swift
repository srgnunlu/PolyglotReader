import SwiftUI
import Supabase

@main
struct PolyglotReaderApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var errorHandlingService = ErrorHandlingService.shared

    init() {
        SecurityManager.shared.configure()
        ErrorHandlingService.shared.configureGlobalHandlers()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(settingsViewModel)
                .environmentObject(errorHandlingService)
                .preferredColorScheme(settingsViewModel.colorScheme)
                .onOpenURL { url in
                    // Handle OAuth callback
                    Task {
                        await handleOAuthCallback(url: url)
                    }
                }
        }
    }

    private func handleOAuthCallback(url: URL) async {
        logDebug("App", "OAuth callback alındı")

        // Extract tokens from URL fragment
        guard let fragment = url.fragment else {
            logWarning("App", "No fragment in callback URL")
            return
        }

        // Parse the fragment for access_token and refresh_token
        let params = fragment.components(separatedBy: "&").reduce(into: [String: String]()) { result, item in
            let parts = item.components(separatedBy: "=")
            if parts.count == 2 {
                result[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
            }
        }

        if let accessToken = params["access_token"], let refreshToken = params["refresh_token"] {
            logInfo("App", "Got tokens from OAuth callback")
            do {
                // Set the session using SupabaseService
                try await SupabaseService.shared.handleOAuthCallback(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )

                // Update auth state
                await MainActor.run {
                    authViewModel.currentUser = SupabaseService.shared.currentUser
                    authViewModel.isAuthenticated = true
                }
            } catch {
                logError("App", "Failed to set session: \(error)")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var errorHandlingService: ErrorHandlingService

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
        .overlay(alignment: .top) {
            if let banner = errorHandlingService.banner {
                ErrorBannerView(banner: banner) {
                    errorHandlingService.dismissBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .alert(
            item: Binding(
                get: { errorHandlingService.alert },
                set: { _ in errorHandlingService.dismissAlert() }
            )
        ) { alert in
            buildAlert(for: alert)
        }
        .onAppear {
            errorHandlingService.recordAppState(
                currentScreen: authViewModel.isAuthenticated ? "MainTab" : "Auth",
                isAuthenticated: authViewModel.isAuthenticated
            )
        }
        .onChange(of: authViewModel.isAuthenticated) { newValue in
            errorHandlingService.recordAppState(
                currentScreen: newValue ? "MainTab" : "Auth",
                isAuthenticated: newValue
            )
        }
    }

    private func buildAlert(for alert: ErrorHandlingService.ErrorAlert) -> Alert {
        let messageText = [alert.message, alert.suggestion]
            .compactMap { $0 }
            .joined(separator: "\n")

        if let retryAction = alert.retryAction, let helpAction = alert.helpAction {
            return Alert(
                title: Text(alert.title),
                message: Text(messageText),
                primaryButton: .default(Text(NSLocalizedString("error.action.retry", comment: ""))) {
                    retryAction()
                    errorHandlingService.dismissAlert()
                },
                secondaryButton: .default(Text(NSLocalizedString("error.action.help", comment: ""))) {
                    helpAction()
                    errorHandlingService.dismissAlert()
                }
            )
        }

        if let helpAction = alert.helpAction {
            return Alert(
                title: Text(alert.title),
                message: Text(messageText),
                primaryButton: .default(Text(NSLocalizedString("error.action.help", comment: ""))) {
                    helpAction()
                    errorHandlingService.dismissAlert()
                },
                secondaryButton: .cancel(Text(NSLocalizedString("error.action.dismiss", comment: ""))) {
                    errorHandlingService.dismissAlert()
                }
            )
        }

        return Alert(
            title: Text(alert.title),
            message: Text(messageText),
            dismissButton: .default(Text(NSLocalizedString("error.action.dismiss", comment: ""))) {
                errorHandlingService.dismissAlert()
            }
        )
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var errorHandlingService: ErrorHandlingService

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("Kütüphane", systemImage: "books.vertical")
                }
                .tag(0)

            NotebookView()
                .tabItem {
                    Label("Defterim", systemImage: "bookmark.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Ayarlar", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(.indigo)
        .onChange(of: selectedTab) { newValue in
            errorHandlingService.recordAppState(
                currentScreen: tabName(for: newValue),
                selectedTab: newValue
            )
        }
    }

    private func tabName(for index: Int) -> String {
        switch index {
        case 0: return "Library"
        case 1: return "Notebook"
        case 2: return "Settings"
        default: return "MainTab"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(SettingsViewModel())
}
