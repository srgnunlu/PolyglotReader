import SwiftUI

// MARK: - Splash Overlay
/// Brand moment on cold start (≤1s total): the glass logo appears over the
/// same editorial background AuthView uses, then the overlay fades out while
/// AuthView's own brand lockup picks up the motion — a scale+fade handoff.
/// Also masks the brief session-restore flicker before auth state resolves.
struct SplashOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            CorioEntryBackground()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DSColor.brand.opacity(0.16), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                CorioBrandMark(size: 96)
                    .dsShadow(.floating)
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1 : 0)
            .accessibilityHidden(true)
        }
        .onAppear {
            withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }
}

#Preview {
    SplashOverlayView()
}
