import SwiftUI

// MARK: - Folder Card View
/// iOS native tarzı klasör kartı
struct FolderCardView: View {
    let folder: Folder
    var onTap: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Klasör ikonu
                Image(systemName: folder.sfSymbol)
                    .font(.system(size: 36))
                    .foregroundStyle(Color(hex: folder.color) ?? .indigo)

                // Klasör adı
                Text(folder.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // Dosya sayısı
                Text("library.file_count".localized(with: folder.fileCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("common.delete".localized, systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Collapsible Folder Section
/// Açılıp kapanabilen klasör bölümü - LiquidGlass tasarım
struct CollapsibleFolderSection: View {
    @ObservedObject var viewModel: LibraryViewModel
    @AppStorage("areFoldersCollapsed") private var isCollapsed: Bool = false
    @State private var folderToEdit: Folder?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık - tıklanabilir
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // LiquidGlass ikon
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 28, height: 28)

                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.indigo)
                    }

                    Text("library.folders".localized)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("(\(viewModel.folders.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Klasör grid - animasyonlu açılış/kapanış
            if !isCollapsed {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(viewModel.folders) { folder in
                        LiquidGlassFolderCard(folder: folder) {
                            viewModel.navigateToFolder(folder)
                        } onDelete: {
                            Task { await viewModel.deleteFolder(folder) }
                        } onEdit: {
                            folderToEdit = folder
                        } onDropFiles: { fileIds in
                            Task { await viewModel.moveFilesByIds(fileIds, to: folder) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .background {
            LiquidGlassBackground(
                cornerRadius: 16,
                intensity: .light,
                accentColor: .indigo
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .sheet(item: $folderToEdit) { folder in
            FolderEditorSheet(viewModel: viewModel, folderToEdit: folder)
                .presentationCornerRadius(DSRadius.popup)
        }
    }
}

// MARK: - LiquidGlass Folder Card
/// LiquidGlass tasarımlı klasör kartı
struct LiquidGlassFolderCard: View {
    let folder: Folder
    var onTap: () -> Void
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    /// Dosya kartından sürüklenen dosya ID'leri bu klasöre bırakıldığında çağrılır.
    var onDropFiles: (([String]) -> Void)?

    @State private var showDeleteConfirmation = false
    @State private var isDropTargeted = false

    private var folderColor: Color {
        Color(hex: folder.color) ?? .indigo
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // LiquidGlass klasör ikonu
                ZStack {
                    // Arka plan - blur ve renk
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(folderColor.opacity(0.15))
                        }
                        .overlay {
                            // Üst parlama
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                                .padding(1)
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.5),
                                            folderColor.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                        .frame(width: 38, height: 38)

                    // Klasör ikonu
                    Image(systemName: folder.sfSymbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(folderColor)
                        .shadow(color: folderColor.opacity(0.3), radius: 2, x: 0, y: 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Klasör adı
                    Text(folder.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    // Dosya sayısı
                    Text("library.file_count".localized(with: folder.fileCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    // Ana blur arka plan
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)

                    // Renkli glow
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            RadialGradient(
                                colors: [
                                    folderColor.opacity(0.08),
                                    .clear
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )

                    // Üst parlama
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Kenar
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .white.opacity(0.2),
                                    folderColor.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            }
        }
        .buttonStyle(LiquidGlassFolderButtonStyle())
        .contextMenu {
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    Label("common.edit".localized, systemImage: "pencil")
                }
            }

            if onDelete != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("common.delete".localized, systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "folder.delete.title".localized(with: folder.name),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("common.delete".localized, role: .destructive) {
                onDelete?()
            }
            Button("common.cancel".localized, role: .cancel) {}
        } message: {
            Text(
                folder.fileCount > 0
                    ? "folder.delete.message.files".localized(with: folder.fileCount)
                    : "common.irreversible".localized
            )
        }
        // Sürüklenen dosya kartını kabul et; hedefken kartı vurgula
        .dropDestination(for: String.self) { fileIds, _ in
            guard let onDropFiles else { return false }
            onDropFiles(fileIds)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(folderColor, lineWidth: 2)
            }
        }
        .scaleEffect(isDropTargeted ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTargeted)
    }
}

// MARK: - LiquidGlass Folder Button Style
struct LiquidGlassFolderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Breadcrumb View
/// Klasör hiyerarşisi navigasyonu
struct BreadcrumbView: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Ana klasör butonu
                Button {
                    viewModel.navigateToFolder(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                        Text("library.root_folder".localized)
                    }
                    .foregroundStyle(viewModel.currentFolder == nil ? Color.primary : Color.indigo)
                }

                // Klasör yolu
                ForEach(viewModel.folderPath) { folder in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(folder.name) {
                        viewModel.navigateToPathFolder(folder)
                    }
                    .foregroundStyle(folder.id == viewModel.currentFolder?.id ? .primary : .secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal)
        }
    }
}

// MARK: - Folder Editor Sheet
/// Klasör oluşturma VE düzenleme sheet'i — `folderToEdit` verilirse düzenleme
/// modunda açılır (üst klasör seçici gizlenir; taşıma ayrı bir işlemdir).
struct FolderEditorSheet: View {
    @ObservedObject var viewModel: LibraryViewModel
    var folderToEdit: Folder?
    @Environment(\.dismiss) private var dismiss

    @State private var folderName = ""
    @State private var selectedColor = "#6366F1"
    @State private var selectedIcon = "folder.fill"
    @State private var selectedParentId: UUID?

    private var isEditing: Bool { folderToEdit != nil }

    private let colors = [
        "#6366F1", // indigo
        "#3B82F6", // blue
        "#22C55E", // green
        "#F59E0B", // amber
        "#EF4444", // red
        "#EC4899", // pink
        "#8B5CF6", // violet
        "#14B8A6"  // teal
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("folder.editor.name_section".localized) {
                    TextField("folder.editor.name_placeholder".localized, text: $folderName)
                }

                if !isEditing {
                    Section("folder.editor.parent_section".localized) {
                        Picker("folder.editor.location".localized, selection: $selectedParentId) {
                            Text("library.root_folder".localized).tag(UUID?.none)
                            // Tüm hiyerarşi, em-space girintisiyle
                            ForEach(viewModel.folderTree, id: \.folder.id) { item in
                                Label(
                                    String(repeating: "\u{2003}", count: item.depth) + item.folder.name,
                                    systemImage: item.folder.sfSymbol
                                )
                                .tag(UUID?.some(item.folder.id))
                            }
                        }
                    }
                }

                Section("folder.editor.icon_section".localized) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(FolderIconStore.availableIcons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .foregroundStyle(
                                    selectedIcon == icon ? (Color(hex: selectedColor) ?? .indigo) : .secondary
                                )
                                .frame(width: 44, height: 44)
                                .background {
                                    if selectedIcon == icon {
                                        Circle().fill((Color(hex: selectedColor) ?? .indigo).opacity(0.15))
                                    }
                                }
                                .onTapGesture { selectedIcon = icon }
                                .accessibilityLabel(icon)
                                .accessibilityAddTraits(selectedIcon == icon ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("folder.editor.color_section".localized) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .indigo)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .fontWeight(.bold)
                                    }
                                }
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Önizleme
                Section("folder.editor.preview_section".localized) {
                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.system(size: 32))
                            .foregroundStyle(Color(hex: selectedColor) ?? .indigo)

                        Text(folderName.isEmpty ? "folder.editor.name_section".localized : folderName)
                            .foregroundStyle(folderName.isEmpty ? .secondary : .primary)
                    }
                }
            }
            .navigationTitle(
                isEditing ? "folder.editor.edit_title".localized : "folder.create.title".localized
            )
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let folder = folderToEdit {
                    folderName = folder.name
                    selectedColor = folder.color
                    selectedIcon = folder.sfSymbol
                } else if selectedParentId == nil {
                    selectedParentId = viewModel.currentFolder?.id
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "common.save".localized : "folder.create.button".localized) {
                        let name = folderName
                        let color = selectedColor
                        let icon = selectedIcon
                        let parentId = selectedParentId
                        let folder = folderToEdit
                        Task {
                            if let folder {
                                await viewModel.updateFolder(
                                    folder,
                                    name: name,
                                    color: color,
                                    icon: icon
                                )
                            } else {
                                await viewModel.createFolder(
                                    name: name,
                                    color: color,
                                    icon: icon,
                                    parentId: parentId
                                )
                            }
                            dismiss()
                        }
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Folder Picker Sheet
/// Hiyerarşik klasör seçici — toplu taşıma hedefi için tüm ağacı girintili listeler.
struct FolderPickerSheet: View {
    let destinations: [(folder: Folder, depth: Int)]
    var onSelect: (Folder?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    Label("library.root_folder".localized, systemImage: "house.fill")
                        .foregroundStyle(.primary)
                }

                ForEach(destinations, id: \.folder.id) { item in
                    Button {
                        onSelect(item.folder)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.folder.sfSymbol)
                                .foregroundStyle(Color(hex: item.folder.color) ?? .indigo)
                                .frame(width: 24)

                            Text(item.folder.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(item.folder.fileCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, CGFloat(item.depth) * 20)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("pdf_card.move_to_folder".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    FolderCardView(
        folder: Folder(name: "Akademik Makaleler", color: "#6366F1", userId: "test", fileCount: 5)
    ) {
        logDebug("FolderViews", "Preview tapped")
    }
    .padding()
}
