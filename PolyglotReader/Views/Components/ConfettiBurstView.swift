import SwiftUI

// MARK: - Confetti Burst
/// Tek seferlik, KAZANILMIŞ kutlama patlaması (quiz %80+, ilk PDF yüklemesi).
/// Native Canvas + TimelineView — kütüphane yok, ambient döngü yok: parçacıklar
/// ~1.6 saniyede düşer ve view kalıcı olarak boşalır. Reduce Motion'da hiç çizmez.
struct ConfettiBurstView: View {
    private struct Particle {
        let angle: Double      // fırlatma yönü (radyan, yukarı ağırlıklı)
        let speed: Double      // pt/sn
        let spin: Double       // radyan/sn
        let size: CGSize
        let colorIndex: Int
    }

    private static let colors: [Color] = [
        DSColor.brand,
        DSColor.brandSecondary,
        DSColor.aiAccent,
        DSColor.success,
        DSColor.warning
    ]

    private static let duration: TimeInterval = 1.6
    private static let gravity: Double = 900

    private let particles: [Particle]
    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(particleCount: Int = 42) {
        // Deterministic fan-out: evenly spread angles with index-salted jitter
        // so the burst looks organic without touching a RNG every frame.
        particles = (0..<particleCount).map { index in
            let unit = Double(index) / Double(max(particleCount - 1, 1))
            let jitter = (Double((index * 37) % 100) / 100.0 - 0.5) * 0.5
            // -160°..-20°: her şey yukarı doğru fışkırır.
            let angle = (-160.0 + unit * 140.0) * .pi / 180 + jitter
            return Particle(
                angle: angle,
                speed: 380 + Double((index * 53) % 100) * 3.2,
                spin: (Double((index * 29) % 100) / 100.0 - 0.5) * 12,
                size: CGSize(width: 6 + Double((index * 13) % 5), height: 9 + Double((index * 7) % 6)),
                colorIndex: index % Self.colors.count
            )
        }
    }

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    guard elapsed >= 0, elapsed < Self.duration else { return }

                    let origin = CGPoint(x: size.width / 2, y: size.height * 0.4)
                    let fade = 1.0 - elapsed / Self.duration

                    for particle in particles {
                        let dx = cos(particle.angle) * particle.speed * elapsed
                        let dy = sin(particle.angle) * particle.speed * elapsed
                            + 0.5 * Self.gravity * elapsed * elapsed
                        let position = CGPoint(x: origin.x + dx, y: origin.y + dy)

                        var piece = context
                        piece.opacity = fade
                        piece.translateBy(x: position.x, y: position.y)
                        piece.rotate(by: .radians(particle.spin * elapsed))
                        piece.fill(
                            Path(CGRect(
                                x: -particle.size.width / 2,
                                y: -particle.size.height / 2,
                                width: particle.size.width,
                                height: particle.size.height
                            )),
                            with: .color(Self.colors[particle.colorIndex])
                        )
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        ConfettiBurstView()
    }
}
