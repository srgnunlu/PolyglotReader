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
    
    var body: some View {
        NavigationStack {
            libraryContent
                .navigationTitle(viewModel.currentFolder?.name ?? "Kütüphane")
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
                        UploadingOverlay()
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
                EmptyLibraryView(onUpload: { showFileImporter = true })
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
                            text: $viewModel.searchQuery,
                            placeholder: "Dosya ara..."
                        )
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSearchActive = false
                                viewModel.searchQuery = ""
                            }
                        } label: {
                            Text("İptal")
                                .font(.subheadline)
                                .foregroundStyle(.indigo)
                        }
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
                        Text("Bu klasörde dosya yok")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
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
                }
                
                // Görünüm modu değiştir
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.viewMode = viewModel.viewMode == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: viewModel.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
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
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                // Arama butonu
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSearchActive.toggle()
                        if !isSearchActive {
                            viewModel.searchQuery = ""
                        }
                    }
                } label: {
                    Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSearchActive ? Color.indigo : Color.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
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
                
                // Klasör oluştur butonu
                Button {
                    showCreateFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
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
                
                // PDF yükle butonu
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
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
            print("File import error: \(error)")
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.indigo.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(.indigo, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }
            
            Text("Yükleniyor...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Empty Library View
struct EmptyLibraryView: View {
    let onUpload: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 28) {
            // Animasyonlu ikon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.indigo.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 10) {
                Text("Kütüphaneniz Boş")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("PDF yükleyerek başlayın")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button(action: onUpload) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("PDF Yükle")
                }
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .indigo.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .foregroundStyle(.white)
                .shadow(color: .indigo.opacity(0.4), radius: 12, x: 0, y: 6)
            }
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Sort Controls
struct SortControlsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryViewModel.SortOption.allCases, id: \.self) { option in
                    LiquidGlassPillButton(
                        title: option.rawValue,
                        icon: viewModel.sortBy == option ? 
                            (viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down") : nil,
                        isSelected: viewModel.sortBy == option
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.toggleSort(option)
                        }
                    }
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - Uploading Overlay
struct UploadingOverlay: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                }
                
                Text("Yükleniyor...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(36)
            .background {
                LiquidGlassBackground(
                    cornerRadius: 24,
                    intensity: .heavy,
                    accentColor: .indigo
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
        }
        .onAppear { isAnimating = true }
    }
}

#Preview {
    LibraryView()
        .environmentObject(AuthViewModel())
}
