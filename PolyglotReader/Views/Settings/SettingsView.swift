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
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                            }
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.headline)

                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(user.name), \(user.email)")
                    }
                }

                // Appearance Section
                Section("settings.section.appearance".localized) {
                    // Theme Picker
                    HStack {
                        Label("settings.theme".localized, systemImage: "paintbrush")

                        Spacer()

                        Picker("", selection: $settingsViewModel.preferences.theme) {
                            ForEach(UserPreferences.ThemeMode.allCases, id: \.self) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("settings.accessibility.theme".localized)
                    .accessibilityValue(settingsViewModel.preferences.theme.displayName)
                    .accessibilityIdentifier("theme_picker")
                }

                // Features Section
                Section("settings.section.features".localized) {
                    Toggle(isOn: $settingsViewModel.preferences.autoSummary) {
                        Label("settings.auto_summary".localized, systemImage: "doc.text.magnifyingglass")
                    }
                    .tint(.indigo)
                    .accessibilityLabel("settings.accessibility.auto_summary".localized)
                    .accessibilityHint("settings.accessibility.auto_summary.hint".localized)
                    .accessibilityIdentifier("auto_summary_toggle")

                    Toggle(isOn: $settingsViewModel.preferences.enableNotifications) {
                        Label("settings.notifications".localized, systemImage: "bell")
                    }
                    .tint(.indigo)
                    .accessibilityLabel("settings.accessibility.notifications".localized)
                    .accessibilityHint("settings.accessibility.notifications.hint".localized)
                    .accessibilityIdentifier("notifications_toggle")

                    HStack {
                        Label("settings.default_language".localized, systemImage: "globe")

                        Spacer()

                        Picker("", selection: $settingsViewModel.preferences.defaultLanguage) {
                            Text("settings.language.turkish".localized).tag("tr")
                            Text("settings.language.english".localized).tag("en")
                        }
                        .pickerStyle(.menu)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("settings.default_language".localized)
                    .accessibilityValue(
                        settingsViewModel.preferences.defaultLanguage == "tr"
                            ? "settings.language.turkish".localized
                            : "settings.language.english".localized
                    )
                    .accessibilityIdentifier("language_picker")
                }

                // About Section
                Section("settings.section.about".localized) {
                    HStack {
                        Label("settings.version".localized, systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("settings.version".localized)
                    .accessibilityValue("1.0.0")

                    NavigationLink {
                        DebugLogsView()
                    } label: {
                        HStack {
                            Label("settings.debug_logs".localized, systemImage: "ladybug")
                            Spacer()
                            if LoggingService.shared.errorCount > 0 {
                                Text(String(LoggingService.shared.errorCount))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .accessibilityIdentifier("debug_logs_link")

                    if let privacyURL = URL(string: "https://polyglotreader.app/privacy") {
                        Link(destination: privacyURL) {
                            Label("settings.privacy_policy".localized, systemImage: "hand.raised")
                        }
                        .accessibilityIdentifier("privacy_policy_link")
                    }

                    if let termsURL = URL(string: "https://polyglotreader.app/terms") {
                        Link(destination: termsURL) {
                            Label("settings.terms_of_service".localized, systemImage: "doc.text")
                        }
                        .accessibilityIdentifier("terms_link")
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
                            Label("settings.sign_out".localized, systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                    .accessibilityLabel("settings.accessibility.sign_out".localized)
                    .accessibilityHint("settings.accessibility.sign_out.hint".localized)
                    .accessibilityIdentifier("sign_out_button")
                }
            }
            .navigationTitle("settings.title".localized)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
        .environmentObject(SettingsViewModel())
}
