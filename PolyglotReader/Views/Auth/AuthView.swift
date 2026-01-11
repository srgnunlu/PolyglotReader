import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.8),
                    Color.purple.opacity(0.9),
                    Color.indigo
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Decorative Circles
            GeometryReader { geometry in
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .offset(x: -100, y: -100)
                    .blur(radius: 50)

                Circle()
                    .fill(.purple.opacity(0.3))
                    .frame(width: 200, height: 200)
                    .offset(x: geometry.size.width - 100, y: geometry.size.height - 200)
                    .blur(radius: 40)
            }

            VStack(spacing: 40) {
                Spacer()

                // Logo & Title
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)

                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                            .scaleEffect(isAnimating ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 2).repeatForever(), value: isAnimating)
                    }

                    VStack(spacing: 8) {
                        Text("Polyglot Reader")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Akıllı PDF Okuyucu")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Spacer()

                // Features
                VStack(spacing: 16) {
                    FeatureRow(
                        icon: "doc.text.magnifyingglass",
                        title: "PDF Analizi",
                        subtitle: "Yapay zeka ile doküman analizi"
                    )
                    FeatureRow(
                        icon: "character.bubble",
                        title: "Akıllı Çeviri",
                        subtitle: "Anlık metin çevirisi"
                    )
                    FeatureRow(
                        icon: "brain",
                        title: "Quiz Oluştur",
                        subtitle: "AI destekli sınav hazırlığı"
                    )
                }
                .padding(.horizontal, 30)

                Spacer()

                // Sign In Buttons
                VStack(spacing: 16) {
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
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 55)
                    .cornerRadius(16)

                    // Google Sign In Button
                    Button {
                        Task {
                            await authViewModel.signInWithGoogle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text("Google ile Giriş Yap")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(.white)
                        .foregroundStyle(.black)
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 30)

                // Error Message
                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                // Loading Indicator
                if authViewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding()
                }

                Spacer()
                    .frame(height: 20)

                // Terms
                Text(NSLocalizedString(
                    "auth.terms_notice",
                    comment: "Terms and privacy acceptance notice"
                ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.2))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
