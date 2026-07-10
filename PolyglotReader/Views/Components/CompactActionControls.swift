import SwiftUI

// MARK: - Compact Action Button
struct CompactActionButton: View {
    let icon: String
    var isActive: Bool = false
    /// VoiceOver label. Without it the screen reader announces the raw SF Symbol name.
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DSFont.controlIcon)
                .foregroundStyle(isActive ? DSColor.brand : .primary)
                .frame(width: 36, height: 36)
                .background {
                    if isActive {
                        Circle()
                            .fill(DSColor.brand.opacity(0.15))
                            .overlay(
                                Circle()
                                    .stroke(DSColor.brand.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        Circle()
                            .fill(Color(.tertiarySystemBackground).opacity(0.6))
                    }
                }
                .contentShape(Circle())
        }
        .accessibilityLabel(accessibilityLabel ?? "")
        .dsAnimation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - Compact Action Label
struct CompactActionLabel: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(DSFont.controlIcon)
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .background(Color(.tertiarySystemBackground).opacity(0.6))
            .clipShape(Circle())
    }
}
