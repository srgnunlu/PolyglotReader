import AuthenticationServices
import SwiftUI

/// Unified unauthenticated experience: product story, brand, and sign-in in one screen.
struct AuthView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var entryViewModel = EntryExperienceViewModel()
    @State private var resumeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CorioEntryBackground()

                if usesRegularLayout(width: geometry.size.width) {
                    regularLayout(geometry: geometry)
                } else {
                    compactLayout(geometry: geometry)
                }
            }
        }
        .accessibilityIdentifier("entry_experience")
        .onAppear {
            entryViewModel.setReduceMotion(reduceMotion)
            if !reduceMotion {
                entryViewModel.resumeAutoPlay()
                entryViewModel.startAutoPlayLoop()
            }
        }
        .onDisappear {
            resumeTask?.cancel()
            entryViewModel.pauseAutoPlay()
        }
        .onChange(of: reduceMotion) { _, enabled in
            entryViewModel.setReduceMotion(enabled)
            if !enabled {
                entryViewModel.resumeAutoPlay()
                entryViewModel.startAutoPlayLoop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            let isActive = phase == .active
            entryViewModel.setSceneActive(isActive)
            if isActive, !reduceMotion {
                entryViewModel.resumeAutoPlay()
                entryViewModel.startAutoPlayLoop()
            }
        }
    }

    // MARK: - Responsive Layout

    private func usesRegularLayout(width: CGFloat) -> Bool {
        horizontalSizeClass == .regular && width >= 760
    }

    private func compactLayout(geometry: GeometryProxy) -> some View {
        let availableHeight = geometry.size.height
        let demoHeight = max(180, min(360, availableHeight - 390))

        return VStack(spacing: DSSpacing.sm) {
            HStack {
                CorioWordmark()
                Spacer()
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.xs)

            EntryProductDemo(
                phase: entryViewModel.phase,
                reduceMotion: reduceMotion,
                onSelect: selectPhase
            )
            .frame(height: demoHeight)
            .padding(.horizontal, DSSpacing.lg)

            EntryDemoSelector(selectedPhase: entryViewModel.phase, onSelect: selectPhase)
                .padding(.horizontal, DSSpacing.xl)

            Spacer(minLength: DSSpacing.xs)

            signInPanel
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.xs)
        }
    }

    private func regularLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: DSSpacing.xxl) {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                CorioWordmark()

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("entry.hero.title".localized)
                        .font(DSFont.displayTitle)
                        .foregroundStyle(DSColor.brandInk)

                    Text("entry.hero.subtitle".localized)
                        .font(DSFont.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                EntryProductDemo(
                    phase: entryViewModel.phase,
                    reduceMotion: reduceMotion,
                    onSelect: selectPhase
                )
                .frame(maxHeight: min(500, geometry.size.height * 0.58))

                EntryDemoSelector(selectedPhase: entryViewModel.phase, onSelect: selectPhase)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            signInPanel
                .frame(width: 410)
        }
        .padding(.horizontal, max(DSSpacing.xl, geometry.size.width * 0.06))
        .padding(.vertical, DSSpacing.xl)
    }

    // MARK: - Authentication

    private var signInPanel: some View {
        VStack(spacing: DSSpacing.sm) {
            VStack(spacing: DSSpacing.xs) {
                Text("entry.signin.title".localized)
                    .font(DSFont.screenTitle)
                    .foregroundStyle(DSColor.brandInk)
                    .accessibilityAddTraits(.isHeader)

                Text("entry.signin.subtitle".localized)
                    .font(DSFont.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DSSpacing.sm) {
                SignInWithAppleButton(.signIn) { request in
                    authViewModel.prepareAppleSignInRequest(request)
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
                .disabled(authViewModel.isLoading)
                .opacity(authViewModel.isLoading ? 0.55 : 1)
                .accessibilityIdentifier("apple_sign_in_button")
                .accessibilityLabel("auth.accessibility.apple_button".localized)
                .accessibilityHint("auth.accessibility.apple_button.hint".localized)

                Button {
                    Task {
                        await authViewModel.signInWithGoogle()
                    }
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Image("GoogleG")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)

                        Text("auth.sign_in_google".localized)
                            .font(DSFont.cardTitle)
                    }
                    .foregroundStyle(DSColor.brandInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                            .fill(Color(.systemBackground))
                            .overlay {
                                RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                                    .stroke(DSColor.brandInk.opacity(0.16), lineWidth: 1)
                            }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
                }
                .buttonStyle(DSPressableButtonStyle())
                .disabled(authViewModel.isLoading)
                .opacity(authViewModel.isLoading ? 0.55 : 1)
                .accessibilityIdentifier("google_sign_in_button")
                .accessibilityLabel("auth.accessibility.google_button".localized)
                .accessibilityHint("auth.accessibility.google_button.hint".localized)
            }

            statusSection
            termsSection
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                        .stroke(DSColor.brandInk.opacity(0.08), lineWidth: 1)
                }
        }
        .dsShadow(.card, tint: DSColor.brand)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let error = authViewModel.errorMessage {
            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(DSColor.danger)

                Text(error)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DSSpacing.xs)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                    .fill(DSColor.danger.opacity(0.08))
            }
            .accessibilityLabel(error)
        } else if authViewModel.isLoading {
            HStack(spacing: DSSpacing.xs) {
                ProgressView()
                    .tint(DSColor.brand)
                Text("common.loading".localized)
                    .font(DSFont.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("accessibility.loading".localized)
        }
    }

    private var termsSection: some View {
        VStack(spacing: DSSpacing.xs) {
            Text("auth.terms_notice".localized)
                .font(DSFont.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DSSpacing.sm) {
                if let termsURL = URL(string: "https://polyglotreader.app/terms") {
                    Link("settings.terms_of_service".localized, destination: termsURL)
                        .accessibilityHint("auth.accessibility.opens_in_browser".localized)
                }

                Text("•")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                if let privacyURL = URL(string: "https://polyglotreader.app/privacy") {
                    Link("settings.privacy_policy".localized, destination: privacyURL)
                        .accessibilityHint("auth.accessibility.opens_in_browser".localized)
                }
            }
            .font(DSFont.meta.weight(.semibold))
            .tint(DSColor.brand)
        }
    }

    // MARK: - Actions

    private func selectPhase(_ phase: EntryDemoPhase) {
        DSHaptics.selection()
        withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
            entryViewModel.select(phase, source: .user)
        }

        resumeTask?.cancel()
        guard !reduceMotion else { return }

        resumeTask = Task {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            entryViewModel.resumeAutoPlay()
            entryViewModel.startAutoPlayLoop()
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task {
                await authViewModel.handleAppleSignIn(authorization: authorization)
            }
        case .failure(let error):
            authViewModel.handleAppleSignInFailure(error)
        }
    }
}

/// Compatibility wrapper for previews that still reference the old name.
struct AnimatedMeshBackground: View {
    var body: some View {
        CorioEntryBackground()
    }
}

#Preview("Compact") {
    AuthView()
        .environmentObject(AuthViewModel())
}
