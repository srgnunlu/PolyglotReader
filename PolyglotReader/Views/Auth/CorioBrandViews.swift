import SwiftUI

/// Vector Corio Docs mark shared by the splash, entry screen, and marketing captures.
struct CorioBrandMark: View {
    @ScaledMetric(relativeTo: .title) private var defaultSize: CGFloat = 52
    var size: CGFloat?

    var body: some View {
        Image("CorioBrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size ?? defaultSize, height: size ?? defaultSize)
            .accessibilityHidden(true)
    }
}

/// Compact brand lockup that remains legible beside the product demo.
struct CorioWordmark: View {
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            CorioBrandMark()

            VStack(alignment: alignment, spacing: DSSpacing.xxs) {
                Text("auth.app_name".localized)
                    .font(.title2.bold())
                    .foregroundStyle(DSColor.brandInk)

                Text("auth.app_subtitle".localized)
                    .font(DSFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("auth.accessibility.logo".localized)
    }
}

/// Editorial paper canvas with restrained brand light and no decorative blur blobs.
struct CorioEntryBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            DSColor.brandCanvas

            LinearGradient(
                colors: [
                    DSColor.brand.opacity(colorScheme == .dark ? 0.12 : 0.08),
                    .clear,
                    DSColor.brandSecondary.opacity(colorScheme == .dark ? 0.10 : 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                var grid = Path()
                let spacing: CGFloat = 36

                stride(from: CGFloat.zero, through: size.width, by: spacing).forEach { x in
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat.zero, through: size.height, by: spacing).forEach { y in
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }

                context.stroke(grid, with: .color(DSColor.brandInk.opacity(0.025)), lineWidth: 0.5)
            }

            GeometryReader { geometry in
                CorioBrandMark(size: min(geometry.size.width, geometry.size.height) * 0.48)
                    .opacity(colorScheme == .dark ? 0.025 : 0.018)
                    .rotationEffect(.degrees(-12))
                    .position(x: geometry.size.width * 0.88, y: geometry.size.height * 0.16)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview("Brand") {
    ZStack {
        CorioEntryBackground()
        CorioWordmark()
    }
}
