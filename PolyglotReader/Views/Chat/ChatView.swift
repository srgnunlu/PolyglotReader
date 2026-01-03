import SwiftUI
import UIKit // Needed for UIRectCorner

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onNavigateToPage: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    
    // MARK: - Computed Properties
    /// Seçili görselin UIImage'ı
    private var selectedUIImage: UIImage? {
        guard let data = viewModel.selectedImage else { return nil }
        return UIImage(data: data)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background to cover safe area
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Messages
                    ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    onNavigateToPage: onNavigateToPage
                                )
                                .id(message.id)
                            }
                            
                            if viewModel.isLoading {
                                TypingIndicator()
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages.count) { _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.messages.last?.text) { _ in
                        if let lastMessage = viewModel.messages.last {
                            // No animation for streaming updates to avoid jitter
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                
             // Message Input Area
            VStack(spacing: 0) {
                // Soru Önerileri
                if viewModel.messages.isEmpty && !viewModel.isLoading {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ChatViewModel.suggestions) { suggestion in
                                Button {
                                    Task {
                                        await viewModel.sendMessage(suggestion.prompt)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: suggestion.icon)
                                        Text(suggestion.label)
                                    }
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                
                // Image Selection Info Bar
                if viewModel.selectedImage != nil, let uiImage = selectedUIImage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "photo.fill")
                                .foregroundStyle(.indigo)
                            Text("Seçili Görsel")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                viewModel.selectedImage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Görsel önizlemesi
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 100)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                        
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            Task {
                                await viewModel.sendMessageWithImage("Bu görsel nedir? Bana açıklar mısın?")
                            }
                        } label: {
                            Label("Bu görseli sor", systemImage: "sparkles")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.indigo.opacity(0.1))
                                .foregroundStyle(.indigo)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1),
                        alignment: .top
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Text Selection Info Bar
                if let selectedText = viewModel.selectedText, !selectedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "text.magnifyingglass")
                                .foregroundStyle(.indigo)
                            Text("Seçili Metin")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                viewModel.selectedText = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Text(selectedText)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Button {
                            // Prefill or send "Bu metin nedir?"
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            Task {
                                let query = "Şu metin hakkında bilgi ver: \"\(selectedText)\""
                                await viewModel.sendMessage(query)
                                viewModel.selectedText = nil
                            }
                        } label: {
                            Label("Bu metni sor", systemImage: "sparkles")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.indigo.opacity(0.1))
                                .foregroundStyle(.indigo)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1),
                        alignment: .top
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                HStack(alignment: .bottom, spacing: 12) {
                    // Derin Arama Toggle
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.isDeepSearchEnabled.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.isDeepSearchEnabled ? "brain.head.profile.fill" : "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(viewModel.isDeepSearchEnabled ? .purple : .secondary)
                            .scaleEffect(viewModel.isDeepSearchEnabled ? 1.1 : 1.0)
                    }
                    .accessibilityLabel("Derin Arama")
                    .accessibilityHint(viewModel.isDeepSearchEnabled ? "Açık" : "Kapalı")

                    TextField("Bir şey sor...", text: $viewModel.inputText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 25))
                        .focused($isInputFocused)

                    Button {
                        Task {
                            // Eğer görsel seçiliyse görsel ile gönder
                            if viewModel.selectedImage != nil {
                                await viewModel.sendMessageWithImage()
                            } else {
                                await viewModel.sendMessage()
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(.indigo)
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
                }
                .padding()
                .background(.ultraThinMaterial)

                // Derin Arama aktifse bilgi göster
                if viewModel.isDeepSearchEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                        Text("Derin Arama aktif - Yanıtlar daha yavaş olabilir")
                            .font(.caption2)
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                }
            }
            .navigationTitle("AI Asistan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            }
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    let onNavigateToPage: (Int) -> Void
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Context indicator for user messages
                if message.role == .user && message.text.hasPrefix("Bağlam:") {
                    Text("📝 Seçili metin ile")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                // Message content
                if message.role == .model {
                    // Profesyonel Markdown renderer (tablolar, listeler, başlıklar)
                    MarkdownView(text: message.text, onNavigateToPage: onNavigateToPage)
                } else {
                    Text(message.text)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(message.role == .user ? Color.indigo : Color(.secondarySystemBackground))
            .foregroundStyle(message.role == .user ? .white : .primary)
            .clipShape(
                RoundedCorner(
                    radius: 18,
                    corners: message.role == .user ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight]
                )
            )
            
            if message.role == .model { Spacer() }
        }
    }
}

// MARK: - Message Content with Full Markdown Support
struct MessageContent: View {
    let text: String
    let onNavigateToPage: (Int) -> Void
    
    var body: some View {
        // Custom Markdown renderer with table support
        MarkdownView(text: text, onNavigateToPage: onNavigateToPage)
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.indigo)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
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
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Suggestion Chip
struct SuggestionChip: View {
    let label: String
    let icon: String
    let isHighlighted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHighlighted ? Color.indigo.opacity(0.15) : Color(.tertiarySystemBackground))
            .foregroundStyle(isHighlighted ? .indigo : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isHighlighted ? Color.indigo.opacity(0.3) : Color.clear, lineWidth: 1)
            )
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

#Preview {
    ChatView(
        viewModel: ChatViewModel(fileId: "test"),
        onNavigateToPage: { _ in }
    )
}
