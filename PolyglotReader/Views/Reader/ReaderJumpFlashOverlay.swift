import SwiftUI

// MARK: - Reader Jump Flash Overlay
/// Atıf ([Sayfa N]) veya arama sonucundan sayfaya atlandığında sayfanın
/// üzerinde kısa bir sarı "parıltı" — kullanıcıya nereye ışınlandığını
/// söyleyen navigasyon geri bildirimi. Vurgu paletiyle aynı sarı.
///
/// Tetikleme: `trigger` sayacı her artışta bir kez yanıp söner.
struct ReaderJumpFlashOverlay: View {
    let trigger: Int

    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(DSColor.Highlight.yellow.color)
            .opacity(visible ? 0.22 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) {
                guard trigger > 0 else { return }
                flash()
            }
    }

    private func flash() {
        // Tek yumuşak nefes: hızlı belir, yavaş sön. Reduce Motion'da
        // animasyonsuz kısa görünüm yerine hiç yanmaz — bilgi kaybı yok,
        // sayfa zaten değişti.
        guard !reduceMotion else { return }

        withAnimation(.easeIn(duration: 0.12)) {
            visible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.18)) {
            visible = false
        }
    }
}
