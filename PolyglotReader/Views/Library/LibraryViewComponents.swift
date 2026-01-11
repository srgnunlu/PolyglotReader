import SwiftUI

// MARK: - Loading View
struct LoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.indigo.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(.indigo, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }

            Text("Yükleniyor...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Empty Library View
struct EmptyLibraryView: View {
    let onUpload: () -> Void
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.indigo.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("Kütüphaneniz Boş")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("PDF yükleyerek başlayın")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: onUpload) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("PDF Yükle")
                }
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .indigo.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .foregroundStyle(.white)
                .shadow(color: .indigo.opacity(0.4), radius: 12, x: 0, y: 6)
            }
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Sort Controls
struct SortControlsView: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryViewModel.SortOption.allCases, id: \.self) { option in
                    LiquidGlassPillButton(
                        title: option.rawValue,
                        icon: viewModel.sortBy == option ?
                            (viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down") : nil,
                        isSelected: viewModel.sortBy == option
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.toggleSort(option)
                        }
                    }
                }

                Spacer()
            }
        }
    }
}

// MARK: - Uploading Overlay
struct UploadingOverlay: View {
    let progress: Double
    @State private var isAnimating = false

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)
        let percent = Int(clampedProgress * 100)

        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 50, height: 50)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                }

                Text("Yükleniyor... %\(percent)")
                    .font(.headline)
                    .foregroundStyle(.white)

                ProgressView(value: clampedProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 200)
            }
            .padding(36)
            .background {
                LiquidGlassBackground(
                    cornerRadius: 24,
                    intensity: .heavy,
                    accentColor: .indigo
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
        }
        .onAppear { isAnimating = true }
    }
}
