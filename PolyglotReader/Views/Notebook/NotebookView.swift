import SwiftUI

struct NotebookView: View {
    @StateObject private var viewModel = NotebookViewModel()
    @State private var selectedFileForNavigation: PDFDocumentMetadata?
    @State private var selectedPageNumber: Int = 1
    @State private var showingCategory: NotebookCategory?
    @State private var showingFileId: String?
    @State private var showingAllFiles = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDetailViewActive: Bool {
        showingAllFiles || showingCategory != nil || showingFileId != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Premium gradient arka plan
                LinearGradient(
                    colors: [
                        Color(.systemGroupedBackground),
                        Color.purple.opacity(0.04),
                        Color.indigo.opacity(0.02),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if viewModel.isLoading && viewModel.annotations.isEmpty {
                    NotebookLoadingView()
                } else if showingAllFiles {
                    // Tüm dosyalar view
                    AllFilesView(
                        files: viewModel.fileAnnotationCounts,
                        onSelectFile: { fileId in
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                showingAllFiles = false
                                showingFileId = fileId
                            }
                        },
                        onDismiss: {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                showingAllFiles = false
                            }
                        }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                } else if showingCategory != nil || showingFileId != nil {
                    // Kategori veya dosya detay view
                    NotebookCategoryView(
                        viewModel: viewModel,
                        category: showingCategory,
                        fileId: showingFileId,
                        onNavigateToAnnotation: { annotation in
                            navigateToFile(annotation: annotation)
                        },
                        onDismiss: {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                showingCategory = nil
                                showingFileId = nil
                            }
                        }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                } else if viewModel.annotations.isEmpty {
                    EmptyNotebookView(
                        hasFilters: false
                    ) {}
                } else {
                    // Dashboard view
                    NotebookDashboardView(
                        viewModel: viewModel,
                        onSelectCategory: { category in
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                showingCategory = category
                            }
                        },
                        onSelectFile: { fileId in
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                showingFileId = fileId
                            }
                        },
                        onSelectAnnotation: { annotation in
                            navigateToFile(annotation: annotation)
                        },
                        onShowAllFiles: {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                showingAllFiles = true
                            }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .navigationTitle(isDetailViewActive ? "" : "notebook.title".localized)
            .navigationBarTitleDisplayMode(isDetailViewActive ? .inline : .large)
            .navigationBarHidden(isDetailViewActive)
            .toolbar {
                if showingCategory == nil && showingFileId == nil && !showingAllFiles {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await viewModel.refreshAnnotations()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("notebook.accessibility.refresh".localized)
                        .accessibilityHint("notebook.accessibility.refresh.hint".localized)
                        .accessibilityIdentifier("refresh_notebook_button")
                    }
                }
            }
            .task {
                await viewModel.loadDashboard()
            }
            .refreshable {
                await viewModel.refreshAnnotations()
            }
            .alert("common.error".localized, isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("common.ok".localized, role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .fullScreenCover(item: $selectedFileForNavigation) { file in
                PDFReaderView(file: file, initialPage: selectedPageNumber)
            }
        }
    }

    private var navigationTitle: String {
        if showingAllFiles {
            return "notebook.all_files".localized
        }
        if let category = showingCategory {
            return category.rawValue
        }
        if showingFileId != nil {
            return "notebook.file_notes".localized
        }
        return "notebook.title".localized
    }

    // MARK: - Navigation

    private func navigateToFile(annotation: AnnotationWithFile) {
        Task {
            do {
                if let fullMetadata = try await viewModel.getFileMetadata(fileId: annotation.fileId) {
                    await MainActor.run {
                        selectedPageNumber = annotation.pageNumber
                        selectedFileForNavigation = fullMetadata
                    }
                } else {
                    await MainActor.run {
                        viewModel.errorMessage = "notebook.error.file_not_found".localized
                    }
                }
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "\("notebook.error.file_open".localized) \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Premium Loading View
struct NotebookLoadingView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .indigo.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            .accessibilityHidden(true)

            Text("notebook.loading".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("notebook.loading".localized)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Premium Empty Notebook View
struct EmptyNotebookView: View {
    let hasFilters: Bool
    let onResetFilters: () -> Void
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var emptyTitle: String {
        hasFilters ? "notebook.empty.filtered.title".localized : "notebook.empty.title".localized
    }

    private var emptySubtitle: String {
        hasFilters
            ? "notebook.empty.filtered.subtitle".localized
            : "notebook.empty.subtitle".localized
    }

    var body: some View {
        VStack(spacing: 28) {
            // Animasyonlu ikon
            ZStack {
                // Pulsing background
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.purple.opacity(0.12), .indigo.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(isAnimating ? 1.15 : 0.95)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                        value: isAnimating
                    )

                // Secondary glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.purple.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.0 : 1.1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true).delay(0.5),
                        value: isAnimating
                    )

                // Icon
                Image(systemName: hasFilters ? "bookmark.slash" : "bookmark.square")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(emptyTitle)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Text(emptySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            if hasFilters {
                Button(action: onResetFilters) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                        Text("notebook.clear_filters".localized)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(minHeight: 44)
                    .background {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .indigo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clear_filters_button")
            }
        }
        .padding()
        .onAppear { isAnimating = true }
    }
}

// MARK: - Amber Color
extension Color {
    static let amber = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
}

#Preview {
    NotebookView()
}
