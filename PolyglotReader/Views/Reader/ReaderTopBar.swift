import SwiftUI

// MARK: - Reader Top Bar
/// Serbest yüzen cam kapsül: içerik ekranın tamamı, chrome üzerinde yüzer.
/// Tek satırlık orta alan normalde doküman adını gösterir; sayfa değişince
/// kısa süreliğine sayfa sayacına morph'lanır (numericText ile rakamlar akar).
struct ReaderTopBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Binding var showSearch: Bool
    @Binding var showNavigator: Bool
    let onClose: () -> Void
    /// iOS 26: collapsed pill ile aynı id → bar↔pill cam morph'u.
    var glassMorph: DSGlassMorph?

    @State private var showsPageCounter = false
    @State private var counterRevealTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            ReaderIconButton(systemName: "xmark", action: onClose)
                .accessibilityLabel("common.close".localized)

            titleMorphLabel

            Spacer(minLength: DSSpacing.xs)

            ReaderIconButton(systemName: "list.bullet.rectangle") {
                showNavigator = true
            }
            .accessibilityLabel("navigator.title".localized)

            ReaderIconButton(systemName: "magnifyingglass") {
                showSearch = true
            }
            .accessibilityLabel("reader.search".localized)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .dsGlass(.bar, shape: .capsule, morph: glassMorph)
        .dsShadow(.floating)
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, 60)  // Safe area için Dynamic Island altında kalması için
        .onChange(of: viewModel.currentPage) {
            revealPageCounter()
        }
        .onDisappear {
            counterRevealTask?.cancel()
        }
    }

    // MARK: - Title ↔ Page Counter Morph

    private var titleMorphLabel: some View {
        Text(showsPageCounter ? pageCounterText : viewModel.fileMetadata.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .contentTransition(.numericText())
            .dsAnimation(DSMotion.smooth, value: showsPageCounter)
            .dsAnimation(DSMotion.smooth, value: viewModel.currentPage)
            .accessibilityLabel(accessibilityTitle)
    }

    /// Sayfa değişiminde sayacı göster, kısa bir süre sonra başlığa dön.
    private func revealPageCounter() {
        guard viewModel.totalPages > 0 else { return }
        counterRevealTask?.cancel()
        showsPageCounter = true

        counterRevealTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            showsPageCounter = false
        }
    }

    private var pageCounterText: String {
        "reader.page_counter".localized(with: viewModel.currentPage, viewModel.totalPages)
    }

    private var accessibilityTitle: String {
        viewModel.totalPages > 0
            ? "\(viewModel.fileMetadata.name), \(pageCounterText)"
            : viewModel.fileMetadata.name
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
                .font(DSFont.controlIcon)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .dsGlass(.control, shape: .circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collapsed Bar Indicator
struct CollapsedBarIndicator: View {
    enum Position { case top, bottom }
    let position: Position
    /// iOS 26: ilgili bar ile aynı id → bar↔pill cam morph'u.
    var glassMorph: DSGlassMorph?

    var body: some View {
        Capsule()
            .fill(.clear)
            .frame(width: 60, height: 5)
            .dsGlass(.control, shape: .capsule, morph: glassMorph)
            .padding(position == .top ? .top : .bottom, position == .top ? 16 : 24)
    }
}
