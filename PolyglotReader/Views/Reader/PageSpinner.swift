import SwiftUI

// MARK: - Page Spinner (Wheel Picker)
/// iOS native wheel picker ile sayfa seçimi
/// Sayfa numarasına tıklandığında popover açılır
struct PageSpinner: View {
    let currentPage: Int
    let totalPages: Int
    let onPageChange: (Int) -> Void

    @State private var showPicker = false
    @State private var selectedPage: Int = 1

    var body: some View {
        Button {
            selectedPage = currentPage
            showPicker = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Text("\(currentPage)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("/ \(max(totalPages, 1))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 55)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            PagePickerPopover(
                selectedPage: $selectedPage,
                totalPages: totalPages,
                onConfirm: { page in
                    showPicker = false
                    if page != currentPage {
                        onPageChange(page)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                },
                onCancel: {
                    showPicker = false
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Page Picker Popover Content
/// Wheel picker içeren kompakt popover
struct PagePickerPopover: View {
    @Binding var selectedPage: Int
    let totalPages: Int
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("İptal") {
                    onCancel()
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

                Spacer()

                Text("Sayfa Seç")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Button("Git") {
                    onConfirm(selectedPage)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.indigo)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Wheel Picker
            Picker("Sayfa", selection: $selectedPage) {
                ForEach(1...max(totalPages, 1), id: \.self) { page in
                    Text("\(page)")
                        .tag(page)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .onChange(of: selectedPage) { _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .frame(width: 220)
        .background(Color(.systemBackground))
    }
}
