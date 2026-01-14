import SwiftUI
import Combine

// MARK: - Offline Banner View
/// Reusable offline indicator component
/// Shows when device is offline with sync queue status
struct OfflineBannerView: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var syncQueue = SyncQueue.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isVisible = false
    @State private var isExpanded = false

    var body: some View {
        if networkMonitor.isConnected == false || syncQueue.hasPendingOperations {
            VStack(spacing: 0) {
                bannerContent
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(bannerBackground)
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityStatusLabel)
                    .accessibilityValue(isExpanded ? "accessibility.expanded".localized : "accessibility.collapsed".localized)
                    .accessibilityHint("accessibility.double_tap".localized)
                    .accessibilityAddTraits(.isButton)

                if isExpanded {
                    expandedContent
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.4)) {
                    isVisible = true
                }
            }
        }
    }
    
    private var accessibilityStatusLabel: String {
        if !networkMonitor.isConnected {
            return "offline.title".localized
        } else if case .syncing(let progress) = syncQueue.status {
            return "offline.syncing".localized(with: Int(progress * 100))
        } else if syncQueue.hasPendingOperations {
            return "offline.pending".localized(with: syncQueue.pendingCount)
        } else {
            return "offline.connected".localized
        }
    }

    // MARK: - Banner Content

    private var bannerContent: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .font(.system(size: 18, weight: .semibold))
                .accessibilityHidden(true)

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                statusTitle
                    .font(.subheadline.weight(.semibold))

                statusSubtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Sync indicator or chevron
            if syncQueue.hasPendingOperations {
                syncIndicator
            } else {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var statusIcon: some View {
        Group {
            if !networkMonitor.isConnected {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
            } else if case .syncing = syncQueue.status {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
            } else if case .error = syncQueue.status {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var statusTitle: some View {
        Group {
            if !networkMonitor.isConnected {
                Text("offline.title".localized)
            } else if case .syncing(let progress) = syncQueue.status {
                Text("offline.syncing".localized(with: Int(progress * 100)))
            } else if case .error(let message) = syncQueue.status {
                Text(message)
            } else if syncQueue.hasPendingOperations {
                Text("offline.pending".localized(with: syncQueue.pendingCount))
            } else {
                Text("offline.connected".localized)
            }
        }
        .foregroundStyle(networkMonitor.isConnected ? Color.primary : Color.orange)
    }

    private var statusSubtitle: some View {
        Group {
            if !networkMonitor.isConnected {
                Text("offline.subtitle.offline".localized)
            } else if syncQueue.hasPendingOperations {
                Text("offline.subtitle.syncing".localized)
            } else {
                Text(networkMonitor.statusDescription)
            }
        }
    }

    private var syncIndicator: some View {
        HStack(spacing: 6) {
            Text("\(syncQueue.pendingCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.blue))

            if case .syncing = syncQueue.status {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            // Connection details
            if !networkMonitor.isConnected {
                offlineDetails
            } else {
                onlineDetails
            }

            // Retry button
            if !networkMonitor.isConnected == false && syncQueue.hasPendingOperations {
                Button {
                    syncQueue.processQueue()
                } label: {
                    Label("offline.sync_now".localized, systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sync_now_button")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(bannerBackground)
    }

    private var offlineDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(
                icon: "doc.text",
                title: "offline.feature.pdf_reading".localized,
                subtitle: "offline.feature.pdf_reading.subtitle".localized,
                available: true
            )
            detailRow(
                icon: "highlighter",
                title: "offline.feature.notes".localized,
                subtitle: "offline.feature.notes.subtitle".localized,
                available: true
            )
            detailRow(
                icon: "sparkles",
                title: "offline.feature.ai".localized,
                subtitle: "offline.feature.ai.subtitle".localized,
                available: false
            )
            detailRow(
                icon: "arrow.up.doc",
                title: "offline.feature.upload".localized,
                subtitle: "offline.feature.upload.subtitle".localized,
                available: false
            )
        }
    }

    private var onlineDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundStyle(.green)
                Text("\("offline.connection".localized) \(networkMonitor.connectionType.rawValue)")
                    .font(.subheadline)
            }
            .accessibilityElement(children: .combine)

            if networkMonitor.isExpensive {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    Text("offline.mobile_data".localized)
                        .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }

            if syncQueue.pendingCount > 0 {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.blue)
                    Text("offline.pending_sync".localized(with: syncQueue.pendingCount))
                        .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func detailRow(icon: String, title: String, subtitle: String, available: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(available ? .green : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .secondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(available ? "accessibility.selected".localized : "accessibility.not_selected".localized)
    }

    // MARK: - Background

    private var bannerBackground: some View {
        Group {
            if !networkMonitor.isConnected {
                Color.orange.opacity(0.1)
            } else if case .error = syncQueue.status {
                Color.red.opacity(0.1)
            } else {
                Color(.systemBackground).opacity(0.95)
            }
        }
    }
}

// MARK: - Compact Offline Indicator
/// Minimal offline indicator for use in navigation bars
struct OfflineIndicator: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                Text("offline.title".localized)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .background(Capsule().fill(.orange.opacity(0.15)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("offline.title".localized)
        }
    }
}

// MARK: - Preview
#if DEBUG
#Preview("Offline Banner") {
    VStack {
        OfflineBannerView()
        Spacer()
    }
}

#Preview("Offline Indicator") {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    OfflineIndicator()
                }
            }
    }
}
#endif
