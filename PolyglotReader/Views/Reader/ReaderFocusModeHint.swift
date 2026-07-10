import SwiftUI

// MARK: - Focus Mode Hint
/// Odak moduna girişte üstte kısaca beliren cam kapsül — kullanıcıya modun
/// açıldığını söyler ve ekrandan kendiliğinden çekilir. Çıkışta hint yok:
/// geri gelen barların kendisi yeterli geri bildirim.
struct ReaderFocusModeHint: View {
    /// Her artışta hint bir kez gösterilir (odak moduna her girişte).
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var hideTask: Task<Void, Never>?

    private static let displayDuration: UInt64 = 1_600_000_000

    var body: some View {
        VStack {
            if isVisible {
                Label("reader.focus_mode.on".localized, systemImage: "moon.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.xs)
                    .dsGlass(.banner, shape: .capsule)
                    .dsShadow(.card)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            Spacer()
        }
        .padding(.top, 60) // ReaderTopBar ile aynı hat — Dynamic Island altı.
        .allowsHitTesting(false)
        // Dekoratif: VoiceOver zaten iki parmak çift dokunuşu kendine ayırır,
        // bu ipucu yalnızca görsel bir onaydır.
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            show()
        }
        .onDisappear {
            hideTask?.cancel()
        }
    }

    private func show() {
        hideTask?.cancel()
        withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
            isVisible = true
        }

        hideTask = Task {
            try? await Task.sleep(nanoseconds: Self.displayDuration)
            guard !Task.isCancelled else { return }
            withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
                isVisible = false
            }
        }
    }
}

#Preview {
    struct HintPreview: View {
        @State private var count = 0
        var body: some View {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ReaderFocusModeHint(trigger: count)
                Button("Göster") { count += 1 }
            }
        }
    }
    return HintPreview()
}
