import SwiftUI

/// Type-safe navigation routes for the notebook stack.
enum NotebookRoute: Hashable {
    case allFiles
    case category(NotebookCategory)
    case file(String)
}

struct NotebookView: View {
    @StateObject private var viewModel = NotebookViewModel()
    @State private var path: [NotebookRoute] = []
    @State private var selectedFileForNavigation: PDFDocumentMetadata?
    @State private var selectedPageNumber: Int = 1
    @State private var showExport = false

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationTitle("notebook.title".localized)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if !viewModel.annotations.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showExport = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.indigo)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("annotation.export.title".localized)
                            .accessibilityIdentifier("export_notebook_button")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await viewModel.refreshAnnotations() }
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
                .navigationDestination(for: NotebookRoute.self) { route in
                    destination(for: route)
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
                .sheet(isPresented: $showExport) {
                    AnnotationExportView(annotations: viewModel.annotations) {
                        showExport = false
                    }
                }
        }
    }

    // MARK: - Root Content

    @ViewBuilder
    private var rootContent: some View {
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
            } else if viewModel.annotations.isEmpty {
                EmptyNotebookView(
                    hasFilters: false
                ) {
                    // New users have no annotations yet; guide them to the
                    // Library to open a PDF and start highlighting.
                    NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)
                }
            } else {
                NotebookDashboardView(
                    viewModel: viewModel,
                    onSelectCategory: { path.append(.category($0)) },
                    onSelectFile: { path.append(.file($0)) },
                    onSelectAnnotation: { navigateToFile(annotation: $0) },
                    onShowAllFiles: { path.append(.allFiles) }
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destination(for route: NotebookRoute) -> some View {
        switch route {
        case .allFiles:
            AllFilesView(
                files: viewModel.fileAnnotationCounts,
                onSelectFile: { path.append(.file($0)) },
                onDismiss: popPath
            )
            .toolbar(.hidden, for: .navigationBar)

        case .category(let category):
            NotebookCategoryView(
                viewModel: viewModel,
                category: category,
                fileId: nil,
                onNavigateToAnnotation: { navigateToFile(annotation: $0) },
                onDismiss: popPath
            )
            .toolbar(.hidden, for: .navigationBar)

        case .file(let fileId):
            NotebookCategoryView(
                viewModel: viewModel,
                category: nil,
                fileId: fileId,
                onNavigateToAnnotation: { navigateToFile(annotation: $0) },
                onDismiss: popPath
            )
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func popPath() {
        guard !path.isEmpty else { return }
        path.removeLast()
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
                let appError = ErrorHandlingService.mapToAppError(error)
                await MainActor.run {
                    viewModel.errorMessage = "\("notebook.error.file_open".localized) \(appError.localizedDescription)"
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
    let onPrimaryAction: () -> Void
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

            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: hasFilters ? "xmark.circle.fill" : "books.vertical.fill")
                        .font(.system(size: 14))
                    Text(hasFilters ? "notebook.clear_filters".localized : "notebook.empty.cta".localized)
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
            .accessibilityIdentifier(hasFilters ? "clear_filters_button" : "go_to_library_button")
        }
        .padding()
        .onAppear { isAnimating = true }
    }
}

// MARK: - Tab Switching
extension Notification.Name {
    /// Posted when a view wants the main TabView to switch to the Library tab.
    static let switchToLibraryTab = Notification.Name("CorioScan.switchToLibraryTab")
}

// MARK: - Amber Color
extension Color {
    static let amber = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
}

#Preview {
    NotebookView()
}
