import SwiftUI
import Combine

// MARK: - Library Toolbar & File Import
extension LibraryView {
    @ToolbarContentBuilder
    var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 8) {
                // Geri butonu (klasör içindeyken)
                if viewModel.currentFolder != nil {
                    Button {
                        viewModel.navigateBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(DSFont.controlIcon)
                            .foregroundStyle(DSColor.brand)
                            .frame(width: 36, height: 36)
                            .frame(minWidth: 44, minHeight: 44)
                            .dsGlass(.control, shape: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("library.accessibility.back".localized)
                    .accessibilityHint("library.accessibility.back.hint".localized)
                    .accessibilityIdentifier("back_button")
                }

                // Görünüm modu değiştir
                Button {
                    withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                        viewModel.viewMode = viewModel.viewMode == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: viewModel.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(DSFont.controlIcon)
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .dsGlass(.control, shape: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("library.accessibility.view_mode".localized)
                .accessibilityHint("library.accessibility.view_mode.hint".localized)
                .accessibilityIdentifier("view_mode_button")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                // Çoklu seçim modu
                Button {
                    withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                        viewModel.toggleSelectionMode()
                    }
                } label: {
                    Image(systemName: viewModel.isSelectionMode ? "xmark" : "checklist")
                        .font(DSFont.controlIcon)
                        .foregroundStyle(viewModel.isSelectionMode ? DSColor.brand : Color.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .dsGlass(.control, shape: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    viewModel.isSelectionMode
                        ? "library.accessibility.selection_end".localized
                        : "library.accessibility.selection_start".localized
                )
                .accessibilityIdentifier("selection_mode_button")

                // Arama butonu
                Button {
                    withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                        isSearchActive.toggle()
                        if !isSearchActive {
                            searchInput = ""
                            viewModel.updateSearchQuery("")
                        }
                    }
                } label: {
                    Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                        .font(DSFont.controlIcon)
                        .foregroundStyle(isSearchActive ? DSColor.brand : Color.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            if isSearchActive {
                                Circle()
                                    .fill(DSColor.brand.opacity(0.15))
                                    .overlay {
                                        Circle()
                                            .stroke(DSColor.brand.opacity(0.3), lineWidth: 0.5)
                                    }
                            }
                        }
                        .dsGlass(.control, shape: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("library.accessibility.search".localized)
                .accessibilityHint("library.accessibility.search.hint".localized)
                .accessibilityIdentifier("search_button")

                // Klasör oluştur butonu
                Button {
                    showCreateFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(DSFont.controlIcon)
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .dsGlass(.control, shape: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("library.accessibility.create_folder".localized)
                .accessibilityHint("library.accessibility.create_folder.hint".localized)
                .accessibilityIdentifier("create_folder_button")

                // PDF yükle butonu
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(DSFont.controlIconProminent)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            Circle()
                                .fill(DSColor.brandGradient)
                                .shadow(color: DSColor.brand.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("library.accessibility.upload".localized)
                .accessibilityHint("library.accessibility.upload.hint".localized)
                .accessibilityIdentifier("upload_button")
            }
        }
    }

    func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if !urls.isEmpty, let userId = authViewModel.currentUser?.id {
                Task {
                    await viewModel.uploadFiles(urls: urls, userId: userId)
                }
            }
        case .failure(let error):
            logError("LibraryView", "File import error", error: error)
        }
    }
}
