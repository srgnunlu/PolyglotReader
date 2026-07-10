import SwiftUI

// MARK: - Chat History Skeleton
/// Kayıtlı sohbet geçmişi Supabase'den getirilirken mesaj listesinde
/// gösterilen balon iskeletleri — gelen yerleşimin şeklini önceden çizer.
struct ChatHistorySkeleton: View {
    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            bubbleRow(width: 220, height: 56, isModel: true)
            bubbleRow(width: 170, height: 44, isModel: false)
            bubbleRow(width: 240, height: 64, isModel: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("chat.history.loading".localized)
    }

    /// Model balonları solda, kullanıcı balonları sağda — gerçek dizilimle aynı.
    private func bubbleRow(width: CGFloat, height: CGFloat, isModel: Bool) -> some View {
        HStack(spacing: 0) {
            if !isModel { Spacer(minLength: DSSpacing.xl) }

            SkeletonBlock(cornerRadius: DSRadius.medium)
                .frame(maxWidth: width)
                .frame(height: height)

            if isModel { Spacer(minLength: DSSpacing.xl) }
        }
    }
}

#Preview {
    ChatHistorySkeleton()
        .padding()
}
