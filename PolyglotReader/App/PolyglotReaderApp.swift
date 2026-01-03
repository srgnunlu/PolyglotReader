import SwiftUI
import Supabase

@main
struct PolyglotReaderApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(settingsViewModel)
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
        logDebug("App", "OAuth callback URL: \(url)")
        
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
                try await SupabaseService.shared.handleOAuthCallback(accessToken: accessToken, refreshToken: refreshToken)
                
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
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(SettingsViewModel())
}

