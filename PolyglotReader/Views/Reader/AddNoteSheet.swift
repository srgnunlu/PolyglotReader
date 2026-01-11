import SwiftUI

// MARK: - Add Note Sheet
struct AddNoteSheet: View {
    let selectedText: String
    @Binding var noteText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seçilen Metin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(selectedText)
                        .font(.subheadline)
                        .lineLimit(3)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notunuz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Not Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("İptal", action: onCancel)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") {
                        onSave(noteText)
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
