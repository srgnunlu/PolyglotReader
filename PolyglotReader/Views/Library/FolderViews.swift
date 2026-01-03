import SwiftUI

// MARK: - Folder Card View
/// iOS native tarzı klasör kartı
struct FolderCardView: View {
    let folder: Folder
    var onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    
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
                Text("\(folder.fileCount) dosya")
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
                    Label("Sil", systemImage: "trash")
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
                    
                    Text("Klasörler")
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
    }
}

// MARK: - LiquidGlass Folder Card
/// LiquidGlass tasarımlı klasör kartı
struct LiquidGlassFolderCard: View {
    let folder: Folder
    var onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    
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
                    Text("\(folder.fileCount) dosya")
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
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Sil", systemImage: "trash")
                }
            }
        }
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

// MARK: - Compact Folder Card View (Eski - uyumluluk için)
/// Daha kompakt klasör kartı
struct CompactFolderCardView: View {
    let folder: Folder
    var onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        LiquidGlassFolderCard(folder: folder, onTap: onTap, onDelete: onDelete)
    }
}

// MARK: - Folder Section View (Eski - uyumluluk için)
/// Klasörleri grid olarak gösteren bölüm
struct FolderSectionView: View {
    @ObservedObject var viewModel: LibraryViewModel
    
    var body: some View {
        CollapsibleFolderSection(viewModel: viewModel)
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
                        Text("Ana Klasör")
                    }
                    .foregroundStyle(viewModel.currentFolder == nil ? Color.primary : Color.indigo)
                }
                
                // Klasör yolu
                ForEach(viewModel.folderPath) { folder in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button(folder.name) {
                        // Bu klasöre kadar git
                        while let last = viewModel.folderPath.last, last.id != folder.id {
                            viewModel.folderPath.removeLast()
                        }
                        viewModel.currentFolder = folder
                    }
                    .foregroundStyle(folder.id == viewModel.currentFolder?.id ? .primary : .secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal)
        }
    }
}

// MARK: - Create Folder Sheet
/// Yeni klasör oluşturma sheet'i
struct CreateFolderSheet: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var folderName = ""
    @State private var selectedColor = "#6366F1"
    
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
                Section("Klasör Adı") {
                    TextField("Klasör adı girin", text: $folderName)
                }
                
                Section("Renk") {
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
                Section("Önizleme") {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(hex: selectedColor) ?? .indigo)
                        
                        Text(folderName.isEmpty ? "Klasör Adı" : folderName)
                            .foregroundStyle(folderName.isEmpty ? .secondary : .primary)
                    }
                }
            }
            .navigationTitle("Yeni Klasör")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") {
                        Task {
                            await viewModel.createFolder(name: folderName, color: selectedColor)
                            dismiss()
                        }
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    FolderCardView(
        folder: Folder(name: "Akademik Makaleler", color: "#6366F1", userId: "test", fileCount: 5)
    ) {
        print("Tapped")
    }
    .padding()
}
