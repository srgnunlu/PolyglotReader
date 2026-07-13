import SwiftUI

/// Shared visual chrome for the network-free entry product scenes.
struct EntryWindowBar: View {
    let title: String
    let systemImage: String
    let trailingSystemImage: String

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(DSColor.brand)
                .frame(width: 28, height: 28)

            Text(title)
                .font(DSFont.cardTitle)
                .foregroundStyle(DSColor.brandInk)

            Spacer()

            Image(systemName: trailingSystemImage)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }
}

struct DemoPaper<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                            .stroke(DSColor.brandInk.opacity(0.08), lineWidth: 1)
                    }
            }
            .dsShadow(.subtle)
    }
}

struct DemoTextLine: View {
    let width: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(DSColor.brandInk.opacity(0.12))
                .frame(width: geometry.size.width * width, height: 7)
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}
