import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject var viewModel = LibraryViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State var showFileImporter = false
    @State private var selectedFile: PDFDocumentMetadata?
    @State private var showReader = false
    @State var showCreateFolder = false
    @State var isSearchActive = false
    @State var searchInput = ""  // Local state for immediate input
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkMoveDialog = false
    @State private var fileToRename: PDFDocumentMetadata?
    @State private var renameText = ""
    @State private var shareItem: ShareableFile?
    @State private var fileToDelete: PDFDocumentMetadata?
    @State private var fileToMove: PDFDocumentMetadata?
    @State private var showLibraryChat = false
    // İlk PDF yüklemesi kazanılmış bir an — kutlama bir kez, checkmark anında.
    @AppStorage("hasCelebratedFirstUpload") private var hasCelebratedFirstUpload = false
    @State private var showFirstUploadConfetti = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Namespace private var readerZoomNamespace

    var body: some View {
        NavigationStack {
            libraryContent
                .navigationTitle(viewModel.currentFolder?.name ?? "library.title".localized)
                .toolbar {
                    libraryToolbar
                }
                // Kütüphane geneli AI sohbeti — ayrı toolbar bloğu, mevcut
                // libraryToolbar'a dokunmadan eklenir (SwiftUI birleştirir).
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if !viewModel.files.isEmpty {
                            Button {
                                DSHaptics.lightImpact()
                                showLibraryChat = true
                            } label: {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel("library_chat.open".localized)
                            .accessibilityIdentifier("library_chat_button")
                        }
                    }
                }
                .sheet(isPresented: $showLibraryChat) {
                    LibraryChatView(documents: viewModel.files)
                        .presentationCornerRadius(DSRadius.popup)
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: true
                ) { result in
                    handleFileImport(result: result)
                }
                .fullScreenCover(item: $selectedFile) { file in
                    PDFReaderView(file: file)
                        .readerZoomTransition(sourceID: file.id, in: readerZoomNamespace)
                }
                .sheet(isPresented: $showCreateFolder) {
                    FolderEditorSheet(viewModel: viewModel)
                        .presentationCornerRadius(DSRadius.popup)
                }
                .sheet(item: $shareItem) { item in
                    ShareSheet(items: [item.url])
                }
                .task {
                    await viewModel.loadFiles()
                    await viewModel.loadFoldersAndTags()
                }
                .refreshable {
                    await viewModel.loadFiles()
                    await viewModel.loadFoldersAndTags()
                }
                // Pull-to-refresh spinner picks up the brand hue.
                .tint(DSColor.brand)
                .overlay {
                    if viewModel.isUploading {
                        UploadingOverlay(
                            progress: viewModel.uploadProgress,
                            queueIndex: viewModel.uploadQueueIndex,
                            queueTotal: viewModel.uploadQueueTotal
                        )
                    }
                }
                .overlay {
                    if viewModel.isPreparingShare {
                        ZStack {
                            Color.black.opacity(0.3).ignoresSafeArea()
                            ProgressView("library.share.preparing".localized)
                                .padding(24)
                                .dsGlass(.popup, shape: .rounded(DSRadius.popup))
                        }
                    }
                }
                .overlay {
                    // Overlay'in kapanışından bağımsız yaşar: finalize hızlı
                    // bitse bile konfeti 1.6 saniyesini tamamlar.
                    if showFirstUploadConfetti {
                        ConfettiBurstView()
                            .ignoresSafeArea()
                    }
                }
                .onChange(of: viewModel.uploadProgress) { progress in
                    celebrateFirstUploadIfNeeded(progress: progress)
                }
                // ErrorHandlingService'ten geçmeyen hatalar (offline, toplu işlem
                // özetleri) yalnız errorMessage'a yazılır — burada gösterilir.
                .alert(
                    "common.error".localized,
                    isPresented: Binding(
                        get: { viewModel.errorMessage != nil },
                        set: { if !$0 { viewModel.errorMessage = nil } }
                    )
                ) {
                    Button("common.ok".localized, role: .cancel) {}
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
                .alert(
                    "library.action.rename".localized,
                    isPresented: Binding(
                        get: { fileToRename != nil },
                        set: { if !$0 { fileToRename = nil } }
                    )
                ) {
                    TextField("library.rename.placeholder".localized, text: $renameText)
                    Button("common.save".localized) {
                        if let file = fileToRename {
                            let newName = renameText
                            Task { await viewModel.renameFile(file, to: newName) }
                        }
                        fileToRename = nil
                    }
                    Button("common.cancel".localized, role: .cancel) {
                        fileToRename = nil
                    }
                } message: {
                    Text("library.rename.hint".localized)
                }
                .overlay(alignment: .bottom) {
                    if let toast = viewModel.undoToast {
                        UndoSnackbar(message: toast.message) {
                            Task { await viewModel.performUndo() }
                        }
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(
                    DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion),
                    value: viewModel.undoToast?.id
                )
                // "Open in / Corio Docs'a kopyala" ile gelen PDF'ler burada tüketilir.
                .onReceive(PendingFileImportStore.shared.$pendingURLs) { urls in
                    guard !urls.isEmpty, let userId = authViewModel.currentUser?.id else { return }
                    let toImport = PendingFileImportStore.shared.drain()
                    Task { await viewModel.uploadFiles(urls: toImport, userId: userId) }
                }
        }
    }

    // MARK: - Card Actions

    private func startRename(_ file: PDFDocumentMetadata) {
        // Uzantı düzenleme alanında gösterilmez; VM kaydederken geri ekler.
        renameText = (file.name as NSString).deletingPathExtension
        fileToRename = file
    }

    private func shareFile(_ file: PDFDocumentMetadata) {
        Task {
            if let url = await viewModel.downloadFileForSharing(file) {
                shareItem = ShareableFile(url: url)
            }
        }
    }

    // MARK: - First Upload Celebration
    /// Checkmark anında (progress %100'e sabitlenince) tetiklenir. `files` bu
    /// anda henüz yeni dosyayı içermez — boş kütüphane = gerçek ilk yükleme.
    private func celebrateFirstUploadIfNeeded(progress: Double) {
        guard progress >= 1.0,
              viewModel.isUploading,
              !hasCelebratedFirstUpload,
              viewModel.files.isEmpty else { return }

        hasCelebratedFirstUpload = true
        showFirstUploadConfetti = true

        Task {
            // ConfettiBurstView ~1.6 sn'de boşalır; sonra view'ı kaldır.
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            showFirstUploadConfetti = false
        }
    }
}

// MARK: - Content, Toolbar & Import
extension LibraryView {
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

            if viewModel.isLoading && viewModel.files.isEmpty {
                // İlk yükleme: spinner yerine içerik vaadeden skeleton grid.
                // Yenilemede (files dolu) mevcut içerik yerinde kalır.
                LibrarySkeletonGrid()
            } else if viewModel.filteredFiles.isEmpty && viewModel.folders.isEmpty && !viewModel.isLoading {
                EmptyLibraryView { showFileImporter = true }
            } else if viewModel.viewMode == .list {
                fileListContainer
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
            "library.bulk_delete.confirm".localized(with: viewModel.selectedCount),
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("common.delete".localized, role: .destructive) {
                Task { await viewModel.deleteSelectedFiles() }
            }
            Button("common.cancel".localized, role: .cancel) {}
        }
        .sheet(isPresented: $showBulkMoveDialog) {
            FolderPickerSheet(destinations: viewModel.folderTree) { folder in
                Task { await viewModel.moveSelectedFiles(to: folder) }
            }
        }
        // Liste modundaki swipe aksiyonları: silme onayı + taşıma hedefi
        .confirmationDialog(
            "library.delete.confirm".localized,
            isPresented: Binding(
                get: { fileToDelete != nil },
                set: { if !$0 { fileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("common.delete".localized, role: .destructive) {
                if let file = fileToDelete {
                    Task { await viewModel.deleteFile(file) }
                }
                fileToDelete = nil
            }
            Button("common.cancel".localized, role: .cancel) {
                fileToDelete = nil
            }
        }
        .sheet(item: $fileToMove) { file in
            FolderPickerSheet(destinations: viewModel.folderTree) { folder in
                Task { await viewModel.moveFile(file, to: folder) }
            }
        }
    }

    // MARK: - Selection Action Bar
    private var selectionActionBar: some View {
        HStack(spacing: 20) {
            Button {
                viewModel.selectAllVisible()
            } label: {
                Label("library.selection.all".localized, systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier("select_all_button")

            Spacer()

            Text("library.selection.count".localized(with: viewModel.selectedCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            BulkTagButton(viewModel: viewModel)

            Button {
                showBulkMoveDialog = true
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(viewModel.selectedCount == 0 || viewModel.allFolders.isEmpty)
            .accessibilityLabel("library.selection.move".localized)

            Button {
                showBulkDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(viewModel.selectedCount == 0)
            .accessibilityLabel("library.selection.delete".localized)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Arama, breadcrumb, filtre ve klasör bölümü — grid ve liste modunun
    /// ortak üst alanı.
    @ViewBuilder
    private var listHeaderSection: some View {
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

        // Kaldığın yerden devam (ana klasörde, arama/seçim yokken)
        if viewModel.currentFolder == nil,
           !isSearchActive,
           !viewModel.isSelectionMode,
           !viewModel.continueReadingFiles.isEmpty {
            ContinueReadingStrip(files: viewModel.continueReadingFiles) { file in
                selectedFile = file
            }
        }

        // Kompakt filtre çubuğu (sıralama + etiket)
        CompactFilterBar(viewModel: viewModel)

        // Klasörler — loadFoldersAndTags mevcut seviyenin alt klasörlerini
        // yükler; bölüm her seviyede görünmeli ki iç içe klasörler gezilebilsin.
        if !viewModel.folders.isEmpty {
            CollapsibleFolderSection(viewModel: viewModel)
        }

        // Son Silinenler (ana klasörde ve çöp doluyken)
        if viewModel.currentFolder == nil, !viewModel.trashedFiles.isEmpty {
            TrashRowButton(viewModel: viewModel)
        }
    }

    /// Boş durumlar ayrışır: filtre sonucu boş ≠ klasör boş.
    private var emptyFilterStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.selectedTags.isEmpty ? "doc.text" : "tag.slash")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(
                viewModel.selectedTags.isEmpty
                    ? "library.no_files_in_folder".localized
                    : "library.no_files_filtered".localized
            )
            .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Grid Mode

    private var fileScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                listHeaderSection

                if viewModel.filteredFiles.isEmpty {
                    emptyFilterStateView
                } else {
                    fileGrid
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var fileGrid: some View {
        // Adaptive: iPhone'da 2, iPad/yatayda genişliğe göre 3-5 sütun.
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 160), spacing: 16)
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
                                await viewModel.generateSummary(for: file, force: force)
                            },
                            onMoveToFolder: { folder in
                                Task { await viewModel.moveFile(file, to: folder) }
                            },
                            onRename: { startRename(file) },
                            onShare: { shareFile(file) },
                            onToggleFavorite: {
                                Task { await viewModel.toggleFavorite(file) }
                            },
                            availableFolders: viewModel.moveDestinations,
                            isThumbnailLoading: viewModel.isThumbnailPending(file)
                        )
                    }
                }
                .id(file.id)
                .readerZoomSource(id: file.id, in: readerZoomNamespace)
                .libraryCardScrollTransition()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - List Mode

    /// Liste modu gerçek `List` üzerinde çalışır: iOS'un yerleşik swipe
    /// aksiyonları (sil/taşı/paylaş) burada gelir; grid modunda context menü
    /// aynı işlevleri sağlar.
    private var fileListContainer: some View {
        List {
            Group {
                listHeaderSection
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if viewModel.filteredFiles.isEmpty {
                emptyFilterStateView
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
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
                        onMoveToFolder: { folder in
                            Task { await viewModel.moveFile(file, to: folder) }
                        },
                        onRename: { startRename(file) },
                        onShare: { shareFile(file) },
                        onToggleFavorite: {
                            Task { await viewModel.toggleFavorite(file) }
                        },
                        availableFolders: viewModel.moveDestinations,
                        isSelectionMode: viewModel.isSelectionMode,
                        isSelected: viewModel.isSelected(file),
                        isThumbnailLoading: viewModel.isThumbnailPending(file)
                    )
                    .readerZoomSource(id: file.id, in: readerZoomNamespace)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !viewModel.isSelectionMode {
                            Button(role: .destructive) {
                                fileToDelete = file
                            } label: {
                                Label("common.delete".localized, systemImage: "trash")
                            }

                            Button {
                                fileToMove = file
                            } label: {
                                Label("library.action.move".localized, systemImage: "folder")
                            }
                            .tint(.indigo)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !viewModel.isSelectionMode {
                            Button {
                                Task { await viewModel.toggleFavorite(file) }
                            } label: {
                                Label(
                                    file.isFavorite
                                        ? "library.favorite.remove_short".localized
                                        : "library.favorite".localized,
                                    systemImage: file.isFavorite ? "star.slash" : "star"
                                )
                            }
                            .tint(.yellow)

                            Button {
                                shareFile(file)
                            } label: {
                                Label("common.share".localized, systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

}

#Preview {
    LibraryView()
        .environmentObject(AuthViewModel())
}
