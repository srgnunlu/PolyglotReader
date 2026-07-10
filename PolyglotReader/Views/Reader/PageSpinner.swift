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
            DSHaptics.lightImpact()
        } label: {
            HStack(spacing: 4) {
                // Sayfa değişiminde rakamlar akar (dock'taki numericText anı).
                Text("\(currentPage)")
                    .font(DSFont.pageCounter)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: Double(currentPage)))
                    .dsAnimation(DSMotion.snappy, value: currentPage)

                Text("/ \(max(totalPages, 1))")
                    .font(DSFont.pageCounterMeta)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 55)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("reader.page_picker.accessibility".localized(with: currentPage, max(totalPages, 1)))
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            PagePickerPopover(
                selectedPage: $selectedPage,
                totalPages: totalPages,
                onConfirm: { page in
                    showPicker = false
                    if page != currentPage {
                        onPageChange(page)
                        DSHaptics.mediumImpact()
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
                Button("common.cancel".localized) {
                    onCancel()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()

                Text("reader.page_picker.title".localized)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button("reader.page_picker.go".localized) {
                    onConfirm(selectedPage)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.brand)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

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
            .onChange(of: selectedPage) {
                DSHaptics.selection()
            }
        }
        .frame(width: 220)
        .background(Color(.systemBackground))
    }
}
