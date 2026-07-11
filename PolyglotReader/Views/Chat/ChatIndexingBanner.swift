import SwiftUI

// MARK: - Indexleme Durumu Banner (P0)
struct IndexingStatusBanner: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Sadece belirli durumlarda göster
        if shouldShowBanner {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    statusIcon

                    VStack(alignment: .leading, spacing: 2) {
                        // Yüzde rakamları akarak sayar (indexleme başlığı).
                        Text(statusTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .contentTransition(.numericText(value: Double(viewModel.indexingProgress)))
                            .dsAnimation(DSMotion.snappy, value: viewModel.indexingProgress)

                        if let subtitle = statusSubtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Yenile butonu (hata durumunda)
                    if case .failed = viewModel.indexingStatus {
                        Button {
                            Task { await viewModel.refreshIndexingStatus() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("common.retry".localized)
                    }
                }

                // Progress bar (indexleme sırasında) — marka gradyanlı dolgu
                if case .indexing = viewModel.indexingStatus {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(DSColor.brand.opacity(0.15))

                            Capsule()
                                .fill(DSColor.brandGradient)
                                .frame(width: max(geo.size.width * CGFloat(viewModel.indexingProgress), 6))
                        }
                    }
                    .frame(height: 6)
                    .dsAnimation(DSMotion.smooth, value: viewModel.indexingProgress)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .dsAnimation(DSMotion.snappy, value: viewModel.indexingStatus)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusTitle)
        }
    }

    private var shouldShowBanner: Bool {
        switch viewModel.indexingStatus {
        case .unknown, .ready:
            return false
        default:
            return true
        }
    }

    private var statusIcon: some View {
        Group {
            switch viewModel.indexingStatus {
            case .checking:
                ProgressView()
                    .scaleEffect(0.8)
            case .indexing:
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(DSColor.brand)
            case .notIndexed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DSColor.warning)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DSColor.danger)
            default:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DSColor.success)
            }
        }
        .font(.body)
        .accessibilityHidden(true)
    }

    private var statusTitle: String {
        switch viewModel.indexingStatus {
        case .checking:
            return "chat.indexing.checking".localized
        case .indexing:
            let percent = Int(viewModel.indexingProgress * 100)
            return "chat.indexing.indexing".localized(with: percent)
        case .notIndexed:
            return "chat.indexing.not_indexed".localized
        case .failed:
            return "chat.indexing.failed".localized
        case .ready:
            return "chat.indexing.ready".localized
        case .unknown:
            return ""
        }
    }

    private var statusSubtitle: String? {
        switch viewModel.indexingStatus {
        case .indexing:
            return "chat.indexing.subtitle.indexing".localized
        case .notIndexed:
            return "chat.indexing.subtitle.not_indexed".localized
        case .failed(let error):
            return error
        default:
            return nil
        }
    }

    private var backgroundColor: Color {
        switch viewModel.indexingStatus {
        case .failed:
            return DSColor.danger.opacity(0.1)
        case .notIndexed:
            return DSColor.warning.opacity(0.1)
        case .indexing, .checking:
            return DSColor.brand.opacity(0.1)
        default:
            return DSColor.success.opacity(0.1)
        }
    }
}
