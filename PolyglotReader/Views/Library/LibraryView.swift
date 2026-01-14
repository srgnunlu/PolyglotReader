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
                    Color(.systemGroupedBackground),
                    Color.indigo.opacity(0.03),
                    Color(.systemGroupedBackground)
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
                    availableFolders: viewModel.folders
                )
                .id(file.id)
            }
        }
        .padding(.horizontal)
    }

    private var fileList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.filteredFiles) { file in
                PDFListRowView(file: file) {
                    selectedFile = file
                } onDelete: {
                    Task { await viewModel.deleteFile(file) }
                }
                .padding(.horizontal)
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 36, height: 36)
                            .frame(minWidth: 44, minHeight: 44)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("library.accessibility.back".localized)
                    .accessibilityHint("library.accessibility.back.hint".localized)
                    .accessibilityIdentifier("back_button")
                }

                // Görünüm modu değiştir
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.viewMode = viewModel.viewMode == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: viewModel.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("library.accessibility.view_mode".localized)
                .accessibilityHint("library.accessibility.view_mode.hint".localized)
                .accessibilityIdentifier("view_mode_button")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                // Arama butonu
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        isSearchActive.toggle()
                        if !isSearchActive {
                            searchInput = ""
                            viewModel.updateSearchQuery("")
                        }
                    }
                } label: {
                    Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSearchActive ? Color.indigo : Color.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            Group {
                                if isSearchActive {
                                    Circle()
                                        .fill(Color.indigo.opacity(0.15))
                                        .overlay {
                                            Circle()
                                                .stroke(Color.indigo.opacity(0.3), lineWidth: 0.5)
                                        }
                                } else {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                        }
                                }
                            }
                        }
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                }
                        }
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.indigo, .indigo.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .indigo.opacity(0.4), radius: 6, x: 0, y: 3)
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

#Preview {
    LibraryView()
        .environmentObject(AuthViewModel())
}
