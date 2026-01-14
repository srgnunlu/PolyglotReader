import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isAnimating = false
    @State private var floatAnimation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // MARK: - Animated Background
                AnimatedMeshBackground()
                    .ignoresSafeArea()

                // MARK: - Floating Blobs
                FloatingBlobs(geometry: geometry, isAnimating: $floatAnimation, reduceMotion: reduceMotion)
                    .accessibilityHidden(true)

                // MARK: - Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: geometry.size.height * 0.08)

                        // Logo Section
                        logoSection

                        // Features Card
                        featuresCard
                            .padding(.horizontal, 24)

                        Spacer()
                            .frame(height: 16)

                        // Sign In Section
                        signInSection
                            .padding(.horizontal, 24)

                        // Error & Loading
                        statusSection

                        // Terms
                        termsSection

                        Spacer()
                            .frame(height: 32)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                isAnimating = true
            }
            if !reduceMotion {
                floatAnimation = true
            }
        }
    }

    // MARK: - Logo Section
    private var logoSection: some View {
        VStack(spacing: 16) {
            // Glassmorphic Logo Container
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                // Glass container
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 110, height: 110)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)

                // Icon
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0.0)
            }
            .accessibilityLabel("auth.accessibility.logo".localized)

            // App Name
            VStack(spacing: 6) {
                Text("auth.app_name".localized)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white, .white.opacity(0.85)]
                                : [.primary, .primary.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .accessibilityAddTraits(.isHeader)

                Text("auth.app_subtitle".localized)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(isAnimating ? 1.0 : 0.0)
            .offset(y: isAnimating ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.2), value: isAnimating)
        }
    }

    // MARK: - Features Card
    private var featuresCard: some View {
        VStack(spacing: 0) {
            FeatureRowGlass(
                icon: "doc.viewfinder",
                iconColors: [.indigo, .blue],
                title: "auth.feature.pdf_analysis".localized,
                subtitle: "auth.feature.pdf_analysis.subtitle".localized
            )

            Divider()
                .background(.white.opacity(0.1))
                .padding(.horizontal, 16)

            FeatureRowGlass(
                icon: "bubble.left.and.bubble.right.fill",
                iconColors: [.purple, .pink],
                title: "auth.feature.translation".localized,
                subtitle: "auth.feature.translation.subtitle".localized
            )

            Divider()
                .background(.white.opacity(0.1))
                .padding(.horizontal, 16)

            FeatureRowGlass(
                icon: "brain.head.profile",
                iconColors: [.orange, .red],
                title: "auth.feature.quiz".localized,
                subtitle: "auth.feature.quiz.subtitle".localized
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
        )
        .opacity(isAnimating ? 1.0 : 0.0)
        .offset(y: isAnimating ? 0 : 30)
        .animation(.easeOut(duration: 0.6).delay(0.3), value: isAnimating)
    }

    // MARK: - Sign In Section
    private var signInSection: some View {
        VStack(spacing: 14) {
            // Apple Sign In
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    Task {
                        await authViewModel.handleAppleSignIn(authorization: auth)
                    }
                case .failure(let error):
                    logError("AuthView", "Apple Sign In failed", error: error)
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 56)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .accessibilityIdentifier("apple_sign_in_button")
            .accessibilityLabel("auth.accessibility.apple_button".localized)
            .accessibilityHint("auth.accessibility.apple_button.hint".localized)

            // Google Sign In - Glassmorphic Style
            Button {
                Task {
                    await authViewModel.signInWithGoogle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Google "G" icon approximation
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.red, .yellow, .green, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)

                        Text("G")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("auth.sign_in_google".localized)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .foregroundStyle(.primary)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .accessibilityIdentifier("google_sign_in_button")
            .accessibilityLabel("auth.accessibility.google_button".localized)
            .accessibilityHint("auth.accessibility.google_button.hint".localized)
        }
        .opacity(isAnimating ? 1.0 : 0.0)
        .offset(y: isAnimating ? 0 : 30)
        .animation(.easeOut(duration: 0.6).delay(0.4), value: isAnimating)
    }

    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 8) {
            if let error = authViewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.red.opacity(0.1))
                )
                .accessibilityLabel(error)
            }

            if authViewModel.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.indigo)
                    Text("common.loading".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .accessibilityLabel("accessibility.loading".localized)
            }
        }
    }

    // MARK: - Terms Section
    private var termsSection: some View {
        Text("auth.terms_notice".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .opacity(isAnimating ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.6).delay(0.5), value: isAnimating)
    }
}

// MARK: - Animated Mesh Background
struct AnimatedMeshBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    // Dark mode colors
    private var darkColors: [Color] {
        [
            Color(hex: "0f0c29") ?? .indigo,
            Color(hex: "302b63") ?? .purple,
            Color(hex: "24243e") ?? .indigo.opacity(0.8)
        ]
    }

    // Light mode colors
    private var lightColors: [Color] {
        [
            (Color(hex: "667eea") ?? .indigo).opacity(0.3),
            (Color(hex: "764ba2") ?? .purple).opacity(0.2),
            .white
        ]
    }

    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: colorScheme == .dark ? darkColors : lightColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Mesh overlay for depth
            if colorScheme == .light {
                RadialGradient(
                    colors: [.white.opacity(0.8), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                )
            }
        }
    }
}

// MARK: - Floating Blobs
struct FloatingBlobs: View {
    let geometry: GeometryProxy
    @Binding var isAnimating: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // Top-left blob
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.indigo.opacity(0.4), .purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 250, height: 250)
                .blur(radius: 60)
                .offset(
                    x: -geometry.size.width * 0.3 + (isAnimating && !reduceMotion ? 20 : 0),
                    y: -geometry.size.height * 0.15 + (isAnimating && !reduceMotion ? 15 : 0)
                )
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 6).repeatForever(autoreverses: true),
                    value: isAnimating
                )

            // Bottom-right blob
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.35), .pink.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(
                    x: geometry.size.width * 0.35 + (isAnimating && !reduceMotion ? -15 : 0),
                    y: geometry.size.height * 0.3 + (isAnimating && !reduceMotion ? -20 : 0)
                )
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 7).repeatForever(autoreverses: true).delay(0.5),
                    value: isAnimating
                )

            // Center accent blob
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.25), .cyan.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 180, height: 180)
                .blur(radius: 45)
                .offset(
                    x: geometry.size.width * 0.1 + (isAnimating && !reduceMotion ? 25 : 0),
                    y: geometry.size.height * 0.45 + (isAnimating && !reduceMotion ? -10 : 0)
                )
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 8).repeatForever(autoreverses: true).delay(1),
                    value: isAnimating
                )
        }
    }
}

// MARK: - Feature Row Glass
struct FeatureRowGlass: View {
    let icon: String
    let iconColors: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
