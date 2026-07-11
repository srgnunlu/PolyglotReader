import SwiftUI
import UIKit // UIImage

// MARK: - Chat Selection Bars
// Okuyucudan taşınan bağlam (seçili görsel / seçili metin) kompozerin üstünde
// birer bilgi barı olarak durur; tek dokunuşla soruya dönüşür.

struct ChatImageSelectionBar: View {
    @ObservedObject var viewModel: ChatViewModel
    let uiImage: UIImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Image(systemName: "photo.fill")
                    .foregroundStyle(DSColor.brand)
                Text("chat.selected_image".localized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.selectedImage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("chat.accessibility.clear_selection".localized)
            }

            // Görsel önizlemesi
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 100)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.small - 4))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.small - 4)
                        .stroke(Color(.separator), lineWidth: 1)
                }
                .accessibilityLabel("chat.selected_image".localized)

            Button {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                Task {
                    await viewModel.sendMessageWithImage("chat.ask_image_prompt".localized)
                }
            } label: {
                Label("chat.ask_about_image".localized, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(DSColor.brand.opacity(0.1))
                    .foregroundStyle(DSColor.brand)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.small - 4))
            }
            .accessibilityIdentifier("ask_about_image_button")
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
}

struct ChatTextSelectionBar: View {
    @ObservedObject var viewModel: ChatViewModel
    let selectedText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(DSColor.brand)
                Text("chat.selected_text".localized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.selectedText = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("chat.accessibility.clear_selection".localized)
            }

            Text(selectedText)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .padding(DSSpacing.xs)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.small - 4))

            Button {
                // Prefill or send "Bu metin nedir?"
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                Task {
                    let query = "\("chat.ask_text_prompt".localized) \"\(selectedText)\""
                    await viewModel.sendMessage(query)
                    viewModel.selectedText = nil
                }
            } label: {
                Label("chat.ask_about_text".localized, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(DSColor.brand.opacity(0.1))
                    .foregroundStyle(DSColor.brand)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.small - 4))
            }
            .accessibilityIdentifier("ask_about_text_button")
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
}
