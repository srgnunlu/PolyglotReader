import SwiftUI

// MARK: - Reader Top Bar
struct ReaderTopBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Binding var showSearch: Bool
    @Binding var showNavigator: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReaderIconButton(systemName: "xmark", action: onClose)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.fileMetadata.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if viewModel.totalPages > 0 {
                    Text(pageCounterText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ReaderIconButton(systemName: "list.bullet.rectangle") {
                showNavigator = true
            }
            .accessibilityLabel("navigator.title".localized)

            ReaderIconButton(systemName: "magnifyingglass") {
                showSearch = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            LiquidGlassBackground(cornerRadius: 18, intensity: .light, accentColor: .indigo)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .padding(.top, 60)  // Safe area için Dynamic Island altında kalması için
    }

    private var pageCounterText: String {
        "Sayfa \(viewModel.currentPage) / \(viewModel.totalPages)"
    }
}

// MARK: - Reader Icon Button
struct ReaderIconButton: View {
    let systemName: String
    let action: () -> Void
    var isActive: Bool = true

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collapsed Bar Indicator
struct CollapsedBarIndicator: View {
    enum Position { case top, bottom }
    let position: Position

    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
            }
            .frame(width: 60, height: 5)
            .padding(position == .top ? .top : .bottom, position == .top ? 16 : 24)
    }
}
