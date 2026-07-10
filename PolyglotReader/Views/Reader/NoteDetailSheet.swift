import SwiftUI

// MARK: - Note Detail Sheet
struct NoteDetailSheet: View {
    let annotation: Annotation
    let onSave: (String) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var noteText: String = ""
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false

    private let maxCharacters = 500
    private let cornerRadius: CGFloat = DSRadius.popup

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    highlightedTextPreview
                    noteSection
                    timestampFooter
                }
                .padding(.top, 8)
            }

            // Bottom action bar (sadece edit modunda)
            if isEditing {
                editActionBar
            }
        }
        .dsGlass(.popup, shape: .rounded(cornerRadius))
        .dsShadow(.floating)
        .overlay(alignment: .topLeading) {
            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 40, height: 40)
            }
            .padding(.top, 8)
            .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            // Close button
            Button {
                dismissWithAnimation()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .confirmationDialog(
            "Notu silmek istediğinize emin misiniz?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                deleteWithAnimation()
            }
            Button("İptal", role: .cancel) { }
        }
        .onAppear {
            noteText = annotation.note ?? ""
        }
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var highlightedTextPreview: some View {
        // Küçük highlighted text preview
        if let text = annotation.text, !text.isEmpty {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.indigo)
                    .frame(width: 2, height: 20)

                Text(truncatedHighlightedText)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // Not alanı
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notunuz")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                if !isEditing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.caption)
                            Text("Düzenle")
                                .font(.caption)
                        }
                        .foregroundStyle(.indigo)
                    }
                } else {
                    // Karakter sayacı
                    Text(characterCounterText)
                        .font(.caption)
                        .foregroundStyle(noteText.count > 450 ? .indigo : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: noteText.count)
                }
            }

            if isEditing {
                TextEditor(text: $noteText)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Color.indigo.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(12)
            } else {
                Text(noteText.isEmpty ? "Not eklemek için düzenleyin" : noteText)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(noteText.isEmpty ? .secondary : .primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.indigo.opacity(0.08))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 16)
    }

    // Timestamp footer
    private var timestampFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
            Text(timestampText)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var editActionBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    noteText = annotation.note ?? ""
                    isEditing = false
                }
            } label: {
                Text("İptal")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }

            Button {
                saveWithAnimation()
            } label: {
                Text("Kaydet")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.indigo)
                    .cornerRadius(12)
            }
            .disabled(noteText.count > maxCharacters)
            .opacity(noteText.count > maxCharacters ? 0.5 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Drag Handle
    private var dragHandle: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemGray3),
                                Color(.systemGray4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 48, height: 6)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 46, height: 3)
                    .offset(y: -0.5)

                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), Color(.systemGray2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: 48, height: 6)
            }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Helper Functions
    private var characterCounterText: String {
        "\(noteText.count) / \(maxCharacters)"
    }

    private var truncatedHighlightedText: String {
        guard let text = annotation.text else { return "" }
        let cleaned = cleanupText(text)
        let words = cleaned.split(separator: " ")
        let preview = words.prefix(4).joined(separator: " ")
        return words.count > 4 ? "\(preview)..." : preview
    }

    private var timestampText: String {
        if let updated = annotation.updatedAt {
            return "Düzenlendi: \(updated.relativeTimeString())"
        } else {
            return "Eklendi: \(annotation.createdAt.relativeTimeString())"
        }
    }

    private func cleanupText(_ text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: "-\n", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveWithAnimation() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        onSave(noteText)
        isEditing = false

        // Sheet'in kendi dismiss animasyonunu kullan
        onDismiss()
    }

    private func deleteWithAnimation() {
        DSHaptics.mediumImpact()

        onDelete()

        // Sheet'in kendi dismiss animasyonunu kullan
        onDismiss()
    }

    private func dismissWithAnimation() {
        // Sheet'in kendi dismiss animasyonunu kullan - daha profesyonel
        onDismiss()
    }
}
