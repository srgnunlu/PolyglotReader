import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    if let user = authViewModel.currentUser {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.indigo, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 60, height: 60)

                                Text(String(user.name.prefix(1)).uppercased())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.headline)

                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Appearance Section
                Section("Görünüm") {
                    // Theme Picker
                    HStack {
                        Label("Tema", systemImage: "paintbrush")

                        Spacer()

                        Picker("", selection: $settingsViewModel.preferences.theme) {
                            ForEach(UserPreferences.ThemeMode.allCases, id: \.self) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Features Section
                Section("Özellikler") {
                    Toggle(isOn: $settingsViewModel.preferences.autoSummary) {
                        Label("Otomatik Özet", systemImage: "doc.text.magnifyingglass")
                    }
                    .tint(.indigo)

                    Toggle(isOn: $settingsViewModel.preferences.enableNotifications) {
                        Label("Bildirimler", systemImage: "bell")
                    }
                    .tint(.indigo)

                    HStack {
                        Label("Varsayılan Dil", systemImage: "globe")

                        Spacer()

                        Picker("", selection: $settingsViewModel.preferences.defaultLanguage) {
                            Text("Türkçe").tag("tr")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.menu)
                    }
                }

                // About Section
                Section("Hakkında") {
                    HStack {
                        Label("Versiyon", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        DebugLogsView()
                    } label: {
                        HStack {
                            Label("Debug Logları", systemImage: "ladybug")
                            Spacer()
                            if LoggingService.shared.errorCount > 0 {
                                Text(String(LoggingService.shared.errorCount))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(8)
                            }
                        }
                    }

                    if let privacyURL = URL(string: "https://polyglotreader.app/privacy") {
                        Link(destination: privacyURL) {
                            Label("Gizlilik Politikası", systemImage: "hand.raised")
                        }
                    }

                    if let termsURL = URL(string: "https://polyglotreader.app/terms") {
                        Link(destination: termsURL) {
                            Label("Kullanım Koşulları", systemImage: "doc.text")
                        }
                    }
                }

                // Logout Section
                Section {
                    Button(role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Ayarlar")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
        .environmentObject(SettingsViewModel())
}
