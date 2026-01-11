import SwiftUI

// MARK: - Compact Action Button
struct CompactActionButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? .indigo : .primary)
                .frame(width: 36, height: 36)
                .background {
                    if isActive {
                        Circle()
                            .fill(Color.indigo.opacity(0.15))
                            .overlay(
                                Circle()
                                    .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        Circle()
                            .fill(Color(.tertiarySystemBackground).opacity(0.6))
                    }
                }
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - Compact Action Label
struct CompactActionLabel: View {
    let icon: String
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .background(Color(.tertiarySystemBackground).opacity(0.6))
            .clipShape(Circle())
    }
}
