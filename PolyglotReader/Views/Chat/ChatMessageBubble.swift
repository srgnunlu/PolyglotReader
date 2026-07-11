import SwiftUI
import UIKit // UIRectCorner + UIPasteboard

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var showsTimestamp: Bool = false
    /// AI yanıtını sesli okutur (nil ise menüde gösterilmez).
    var onSpeak: ((String) -> Void)?
    /// Son AI yanıtı için "Yanıtı Yeniden Oluştur" (nil ise gösterilmez).
    var onRegenerate: (() -> Void)?
    /// Hata balonundaki inline "Tekrar Dene" (nil ise buton gösterilmez).
    var onRetry: (() -> Void)?
    let onNavigateToPage: (Int) -> Void

    private var isUser: Bool { message.role == .user }
    private var isError: Bool { message.isError == true }
    private var bubbleColor: Color {
        isUser ? DSColor.brand : Color(.secondarySystemBackground)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter
    }()

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: DSSpacing.xxs) {
            HStack(alignment: .bottom, spacing: DSSpacing.xs) {
                if isUser {
                    // Kullanıcı balonu sağa yaslanır; karşı taraf nefes alır.
                    Spacer(minLength: DSSpacing.xxl)
                } else {
                    aiAvatar
                }

                bubbleBody

                if !isUser {
                    Spacer(minLength: DSSpacing.xxl)
                }
            }

            if showsTimestamp {
                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(DSFont.meta)
                    .foregroundStyle(.tertiary)
                    .padding(isUser ? .trailing : .leading, isUser ? DSSpacing.xxs : 34)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isUser
                ? "chat.accessibility.your_message".localized
                : "chat.accessibility.ai_response".localized
        )
        .accessibilityValue(message.text)
    }

    /// AI mesajlarının kimliği: marka gradyanlı küçük avatar, balonun alt
    /// hizasında oturur — kimin konuştuğu bir bakışta anlaşılır.
    private var aiAvatar: some View {
        Circle()
            .fill(DSColor.brandGradient)
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    // Kural: cam yalnızca navigasyon katmanında — balonlar düz yüzey.
    // Kullanıcı balonu marka rengi + ince gölgeyle öne çıkar.
    @ViewBuilder
    private var bubbleBody: some View {
        let bubble = VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            // Context indicator for user messages
            if isUser && message.text.hasPrefix("Bağlam:") {
                Text("chat.context_indicator".localized)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Message content
            if isError {
                errorContent
            } else if message.role == .model {
                // Profesyonel Markdown renderer (tablolar, listeler, başlıklar)
                MarkdownView(text: message.text, onNavigateToPage: onNavigateToPage)
            } else {
                Text(message.text)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleColor)
        .foregroundStyle(isUser ? .white : .primary)
        .overlay(alignment: .bottom) {
            // Streaming: son satır sisin içinden çıkar; bitince maske söner.
            if isStreaming {
                LinearGradient(
                    colors: [bubbleColor.opacity(0), bubbleColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 22)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .clipShape(
            RoundedCorner(
                radius: 18,
                corners: isUser
                    ? [.topLeft, .topRight, .bottomLeft]
                    : [.topLeft, .topRight, .bottomRight]
            )
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
                DSHaptics.lightImpact()
            } label: {
                Label("chat.copy".localized, systemImage: "doc.on.doc")
            }

            ShareLink(item: message.text) {
                Label("chat.share".localized, systemImage: "square.and.arrow.up")
            }

            if !isUser, !isError, let onSpeak {
                Button {
                    DSHaptics.lightImpact()
                    onSpeak(message.text)
                } label: {
                    Label("chat.speak".localized, systemImage: "speaker.wave.2")
                }
            }

            if !isUser, !isError, let onRegenerate {
                Button {
                    DSHaptics.lightImpact()
                    onRegenerate()
                } label: {
                    Label("chat.regenerate".localized, systemImage: "arrow.clockwise")
                }
            }
        }
        .dsAnimation(DSMotion.smooth, value: isStreaming)

        if isUser {
            bubble.dsShadow(.subtle, tint: DSColor.brand)
        } else {
            bubble
        }
    }

    /// Hata balonu: uyarı ikonu + mesaj + inline "Tekrar Dene". Retry artık
    /// yalnızca genel hata banner'ında değil, hatanın olduğu yerde.
    private var errorContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.warning)
                Text(message.text)
                    .font(.subheadline)
            }

            if let onRetry {
                Button {
                    DSHaptics.lightImpact()
                    onRetry()
                } label: {
                    Label("common.retry".localized, systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.brand)
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityIdentifier("chat_retry_button")
            }
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            // Balonlardaki AI avatarıyla aynı kimlik.
            Circle()
                .fill(DSColor.brandGradient)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DSColor.brand)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.0 : 0.5)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .accessibilityLabel("accessibility.loading".localized)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
