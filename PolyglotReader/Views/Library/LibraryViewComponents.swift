import SwiftUI

// MARK: - Loading View
struct LoadingView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .animation(
                        reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            .accessibilityHidden(true)

            Text("common.loading".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("accessibility.loading".localized)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Empty Library View
struct EmptyLibraryView: View {
    let onUpload: () -> Void
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DSColor.brand.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true),
                        value: isAnimating
                    )

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(DSColor.brandGradient)
                    // Gentle float sells "waiting for its first document".
                    .offset(y: isAnimating && !reduceMotion ? -6 : 0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("library.empty.title".localized)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("library.empty.subtitle".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: onUpload) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("library.empty.button".localized)
                }
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(minWidth: 44, minHeight: 44)
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
            .accessibilityLabel("library.empty.button".localized)
            .accessibilityHint("library.accessibility.upload.hint".localized)
            .accessibilityIdentifier("empty_library_upload_button")
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Library Skeleton Grid
/// İlk yüklemede spinner yerine kart iskeletleri — algılanan hız artar,
/// içerik geldiğinde yerleşim zıplamaz.
struct LibrarySkeletonGrid: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160), spacing: 16)
            ], spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonBlock()
                            .frame(height: 130)

                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBlock()
                                .frame(height: 14)
                                .clipShape(Capsule())

                            SkeletonBlock()
                                .frame(width: 110, height: 10)
                                .clipShape(Capsule())
                        }
                        .padding(14)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.secondarySystemBackground).opacity(0.6))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("accessibility.loading".localized)
    }
}

// MARK: - Uploading Overlay
struct UploadingOverlay: View {
    let progress: Double
    /// Çoklu yükleme kuyruğu (1-bazlı). `queueTotal > 1` ise "3/10" satırı görünür.
    var queueIndex: Int = 0
    var queueTotal: Int = 0
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)
        let percent = Int(clampedProgress * 100)
        // Storage upload is done at 100%, but thumbnail/folder finalization
        // may still run — show a brief checkmark moment instead of vanishing.
        let isFinishing = percent >= 100

        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: DSSpacing.md) {
                ZStack {
                    if isFinishing {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundStyle(DSColor.success)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        uploadSpinner
                            .transition(.opacity)
                    }
                }
                .accessibilityHidden(true)

                if queueTotal > 1 {
                    Text("library.upload.queue".localized(with: queueIndex, queueTotal))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(queueIndex)))
                        .dsAnimation(DSMotion.snappy, value: queueIndex)
                }

                Text(
                    isFinishing
                        ? "library.upload.finishing".localized
                        : "library.uploading".localized(with: percent)
                )
                .font(.headline)
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: Double(percent)))
                .dsAnimation(DSMotion.snappy, value: percent)

                ProgressView(value: clampedProgress)
                    .progressViewStyle(.linear)
                    .tint(DSColor.brand)
                    .frame(width: 200)
            }
            .padding(DSSpacing.xl + DSSpacing.xxs)
            .dsGlass(.popup, shape: .rounded(DSRadius.popup))
            .dsShadow(.floating)
            .dsAnimation(DSMotion.snappy, value: isFinishing)
        }
        .dsHaptic(.success, trigger: percent) { old, new in
            old < 100 && new >= 100
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isFinishing
                ? "library.upload.finishing".localized
                : "library.uploading".localized(with: percent)
        )
    }

    private var uploadSpinner: some View {
        ZStack {
            Circle()
                .stroke(DSColor.brand.opacity(0.2), lineWidth: 4)
                .frame(width: 50, height: 50)

            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(DSColor.brand, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Undo Snackbar
/// Taşıma sonrası alttan beliren "Geri Al" çubuğu; 5 sn sonra VM kendiliğinden kapatır.
struct UndoSnackbar: View {
    let message: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.subheadline)
                .foregroundStyle(DSColor.brand)

            Text(message)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Button("library.undo".localized, action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.brand)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("library.undo.accessibility".localized(with: message))
    }
}
