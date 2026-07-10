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

// MARK: - Uploading Overlay
struct UploadingOverlay: View {
    let progress: Double
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
