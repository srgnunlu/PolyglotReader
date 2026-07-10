import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showFileImporter = false
    @State private var selectedFile: PDFDocumentMetadata?
    @State private var showReader = false
    @State private var showCreateFolder = false
    @State private var isSearchActive = false
    @State private var searchInput = ""  // Local state for immediate input
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkMoveDialog = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            libraryContent
                .navigationTitle(viewModel.currentFolder?.name ?? "library.title".localized)
                .toolbar {
                    libraryToolbar
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImport(result: result)
                }
                .fullScreenCover(item: $selectedFile) { file in
                    PDFReaderView(file: file)
                }
                .sheet(isPresented: $showCreateFolder) {
                    CreateFolderSheet(viewModel: viewModel)
                }
                .task {
                    await viewModel.loadFiles()
                    await viewModel.loadFoldersAndTags()
                }
                .refreshable {
                    await viewModel.loadFiles()
                    await viewModel.loadFoldersAndTags()
                }
                .overlay {
                    if viewModel.isUploading {
                        UploadingOverlay(progress: viewModel.uploadProgress)
                    }
                }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        ZStack {
            // Gradient arka plan
            LinearGradient(
                colors: [
                    DSColor.surfacePrimary,
                    DSColor.brand.opacity(0.03),
                    DSColor.surfacePrimary
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if viewModel.isLoading {
                LoadingView()
            } else if viewModel.filteredFiles.isEmpty && viewModel.folders.isEmpty {
                EmptyLibraryView { showFileImporter = true }
            } else {
                fileScrollView
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelectionMode {
                selectionActionBar
            }
        }
        .confirmationDialog(
            "Seçili \(viewModel.selectedCount) dosya silinsin mi?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                Task { await viewModel.deleteSelectedFiles() }
            }
            Button("İptal", role: .cancel) {}
        }
        .confirmationDialog(
            "Klasöre Taşı",
            isPresented: $showBulkMoveDialog,
            titleVisibility: .visible
        ) {
            Button("Ana Klasör") {
                Task { await viewModel.moveSelectedFiles(to: nil) }
            }
            ForEach(viewModel.folders) { folder in
                Button(folder.name) {
                    Task { await viewModel.moveSelectedFiles(to: folder) }
                }
            }
            Button("İptal", role: .cancel) {}
        }
    }

    // MARK: - Selection Action Bar
    private var selectionActionBar: some View {
        HStack(spacing: 20) {
            Button {
                viewModel.selectAllVisible()
            } label: {
                Label("Tümü", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier("select_all_button")

            Spacer()

            Text("\(viewModel.selectedCount) seçili")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showBulkMoveDialog = true
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(viewModel.selectedCount == 0 || viewModel.folders.isEmpty)
            .accessibilityLabel("Klasöre taşı")

            Button {
                showBulkDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(viewModel.selectedCount == 0)
            .accessibilityLabel("Seçilenleri sil")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var fileScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Arama çubuğu - sadece aktifken görünür
                if isSearchActive {
                    HStack {
                        LiquidGlassSearchBar(
                            text: $searchInput,
                            placeholder: "library.search_placeholder".localized
                        )
                        .onChange(of: searchInput) { newValue in
                            viewModel.updateSearchQuery(newValue)
                        }

                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                                isSearchActive = false
                                searchInput = ""
                                viewModel.updateSearchQuery("")
                            }
                        } label: {
                            Text("common.cancel".localized)
                                .font(.subheadline)
                                .foregroundStyle(.indigo)
                        }
                        .accessibilityLabel("common.cancel".localized)
                    }
                    .padding(.horizontal)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }

                // Breadcrumb navigasyonu (klasör içindeysen)
                if !viewModel.folderPath.isEmpty {
                    BreadcrumbView(viewModel: viewModel)
                }

                // Kompakt filtre çubuğu (sıralama + etiket)
                CompactFilterBar(viewModel: viewModel)

                // Klasörler (ana klasördeyken ve klasör varsa)
                if viewModel.currentFolder == nil && !viewModel.folders.isEmpty {
                    CollapsibleFolderSection(viewModel: viewModel)
                }

                // Dosya listesi/grid
                if viewModel.filteredFiles.isEmpty {
                    // Boş klasör durumu
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("library.no_files_in_folder".localized)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                    .accessibilityElement(children: .combine)
                } else if viewModel.viewMode == .grid {
                    fileGrid
                } else {
                    fileList
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var fileGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            ForEach(viewModel.filteredFiles) { file in
                Group {
                    if viewModel.isSelectionMode {
                        PDFCardView(
                            file: file,
                            onTap: { viewModel.toggleSelection(file) },
                            onDelete: {},
                            isSelectionMode: true,
                            isSelected: viewModel.isSelected(file),
                            isThumbnailLoading: viewModel.isThumbnailPending(file)
                        )
                    } else {
                        FlippablePDFCardView(
                            file: file,
                            onTap: { selectedFile = file },
                            onDelete: { Task { await viewModel.deleteFile(file) } },
                            onGenerateSummary: { force in
                                Task { await viewModel.generateSummary(for: file, force: force) }
                            },
                            onMoveToFolder: { folder in
                                Task { await viewModel.moveFile(file, to: folder) }
                            },
                            availableFolders: viewModel.folders,
                            isThumbnailLoading: viewModel.isThumbnailPending(file)
                        )
                    }
                }
                .id(file.id)
                .libraryCardScrollTransition()
            }
        }
        .padding(.horizontal)
    }

    private var fileList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.filteredFiles) { file in
                PDFListRowView(
                    file: file,
                    onTap: {
                        if viewModel.isSelectionMode {
                            viewModel.toggleSelection(file)
                        } else {
                            selectedFile = file
                        }
                    },
                    onDelete: {
                        Task { await viewModel.deleteFile(file) }
                    },
                    isSelectionMode: viewModel.isSelectionMode,
                    isSelected: viewModel.isSelected(file),
                    isThumbnailLoading: viewModel.isThumbnailPending(file)
                )
                .padding(.horizontal)
                .libraryCardScrollTransition()
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
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
                .accessibilityLabel(viewModel.isSelectionMode ? "Seçimi bitir" : "Çoklu seçim")
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

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first, let userId = authViewModel.currentUser?.id {
                Task {
                    await viewModel.uploadFile(url: url, userId: userId)
                }
            }
        case .failure(let error):
            logError("LibraryView", "File import error", error: error)
        }
    }
}

// MARK: - Card Scroll Transition
/// Cards fade+scale slightly at the viewport edges — depth without noise.
private struct LibraryCardScrollTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scrollTransition(.interactive) { [reduceMotion] view, phase in
            view
                .opacity(!reduceMotion && !phase.isIdentity ? 0.55 : 1)
                .scaleEffect(!reduceMotion && !phase.isIdentity ? 0.96 : 1)
        }
    }
}

extension View {
    func libraryCardScrollTransition() -> some View {
        modifier(LibraryCardScrollTransition())
    }
}

#Preview {
    LibraryView()
        .environmentObject(AuthViewModel())
}
