import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Folder Management

    /// Klasöre git
    func navigateToFolder(_ folder: Folder?) {
        if let folder = folder {
            folderPath.append(folder)
            currentFolder = folder
        } else {
            folderPath.removeAll()
            currentFolder = nil
        }
        Task {
            await loadFoldersAndTags()
        }
    }

    /// Bir önceki klasöre dön
    func navigateBack() {
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
        currentFolder = folderPath.last
        Task {
            await loadFoldersAndTags()
        }
    }

    /// Breadcrumb'dan yoldaki bir klasöre atla: yolu o klasöre kadar kırpar
    /// ve o seviyenin alt klasörlerini/etiketlerini yeniden yükler.
    func navigateToPathFolder(_ folder: Folder) {
        guard folderPath.contains(where: { $0.id == folder.id }) else { return }
        while let last = folderPath.last, last.id != folder.id {
            folderPath.removeLast()
        }
        currentFolder = folder
        Task {
            await loadFoldersAndTags()
        }
    }

    /// Yeni klasör oluştur. `parentId` verilmezse mevcut klasörün altına oluşturulur
    /// (iç-içe klasör). İkon hem DB'ye hem yerel depoya yazılır — `folders.icon`
    /// migration'ı henüz uygulanmamışsa DB yazımı sessizce atlanır.
    func createFolder(
        name: String,
        color: String = "#6366F1",
        icon: String? = nil,
        parentId: UUID? = nil
    ) async {
        do {
            let folder = try await supabaseService.createFolder(
                name: name,
                color: color,
                parentId: parentId
            )
            if let icon {
                FolderIconStore.shared.setIcon(icon, for: folder.id)
                try? await supabaseService.updateFolderIcon(id: folder.id.uuidString, icon: icon)
            }
            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Klasör oluşturuldu", details: folder.name)
        } catch {
            // Kullanıcıya sunum ErrorHandlingService banner/alert'i üzerinden yapılır.
            let appError = ErrorHandlingService.mapToAppError(error)
            logError("LibraryViewModel", "Klasör oluşturma hatası", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "CreateFolder"
                ) { [weak self] in
                    Task { await self?.createFolder(name: name, color: color, icon: icon, parentId: parentId) }
                    return
                }
            )
        }
    }

    /// Klasör sil
    func deleteFolder(_ folder: Folder) async {
        do {
            try await supabaseService.deleteFolder(id: folder.id.uuidString)
            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Klasör silindi", details: folder.name)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logError("LibraryViewModel", "Klasör silme hatası", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "DeleteFolder"
                ) { [weak self] in
                    Task { await self?.deleteFolder(folder) }
                    return
                }
            )
        }
    }

    /// Klasör adı/rengi/ikonunu güncelle. İkon güncellemesi ayrı ve hataya
    /// toleranslı — migration eksikse rename/renk yine de çalışır.
    func updateFolder(_ folder: Folder, name: String, color: String, icon: String) async {
        do {
            try await supabaseService.updateFolder(
                id: folder.id.uuidString,
                name: name,
                color: color
            )
            FolderIconStore.shared.setIcon(icon, for: folder.id)
            try? await supabaseService.updateFolderIcon(id: folder.id.uuidString, icon: icon)

            // Breadcrumb ve başlık eski adı göstermesin
            if currentFolder?.id == folder.id {
                currentFolder?.name = name
                currentFolder?.color = color
            }
            if let pathIndex = folderPath.firstIndex(where: { $0.id == folder.id }) {
                folderPath[pathIndex].name = name
                folderPath[pathIndex].color = color
            }

            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Klasör güncellendi", details: name)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logError("LibraryViewModel", "Klasör güncelleme hatası", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "UpdateFolder"
                ) { [weak self] in
                    Task { await self?.updateFolder(folder, name: name, color: color, icon: icon) }
                    return
                }
            )
        }
    }

    // MARK: - Folder Hierarchy

    /// Tüm klasörleri ağaç sırasına göre düzleştirir (derinlikle birlikte) —
    /// taşıma hedefi ve üst klasör seçicilerinde girintili listeleme için.
    var folderTree: [(folder: Folder, depth: Int)] {
        var childrenByParent: [UUID?: [Folder]] = [:]
        for folder in allFolders {
            childrenByParent[folder.parentId, default: []].append(folder)
        }

        var result: [(Folder, Int)] = []
        func appendChildren(of parentId: UUID?, depth: Int) {
            // Döngüsel parent verisi (bozuk kayıt) sonsuz özyinelemeye
            // dönmesin diye derinliği sınırla.
            guard depth <= 10 else { return }
            for folder in childrenByParent[parentId] ?? [] {
                result.append((folder, depth))
                appendChildren(of: folder.id, depth: depth + 1)
            }
        }
        appendChildren(of: nil, depth: 0)
        return result
    }

    /// Context menü taşıma hedefleri: hiyerarşi em-space girintisiyle tek düz
    /// listeye indirgenir (Menu iç içe yapıyı desteklemediği için).
    var moveDestinations: [Folder] {
        folderTree.map { item in
            var display = item.folder
            display.name = String(repeating: "\u{2003}", count: item.depth) + item.folder.name
            return display
        }
    }

    /// Dosyayı klasöre taşı
    func moveFile(_ file: PDFDocumentMetadata, to folder: Folder?) async {
        let previousFolderId = file.folderId
        do {
            try await supabaseService.moveFileToFolder(
                fileId: file.id,
                folderId: folder?.id
            )
            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index].folderId = folder?.id
            }
            // Girintili görüntü kopyasından gelen em-space'leri mesajda temizle
            let folderName = folder?.name.trimmingCharacters(in: .whitespaces) ?? "Ana Klasör"
            offerUndo(message: "\"\(file.name)\" → \(folderName)") { [weak self] in
                await self?.restoreFolderAssignments([(file.id, previousFolderId)])
            }
            await loadFoldersAndTags()
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "MoveFile"
                ) { [weak self] in
                    Task { await self?.moveFile(file, to: folder) }
                    return
                }
            )
        }
    }

    // MARK: - Undo

    /// "Geri Al" snackbar'ını gösterir; 5 sn sonra kendiliğinden kaybolur.
    func offerUndo(message: String, action: @escaping @MainActor () async -> Void) {
        let toast = UndoToast(message: message, action: action)
        undoToast = toast

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            // Bu sırada yeni bir işlem olduysa onun snackbar'ına dokunma.
            if self?.undoToast?.id == toast.id {
                self?.undoToast = nil
            }
        }
    }

    /// Gösterilen snackbar'ın geri alma eylemini çalıştırır.
    func performUndo() async {
        guard let toast = undoToast else { return }
        undoToast = nil
        await toast.action()
    }

    /// Taşıma geri alması: dosyaları önceki klasörlerine döndürür.
    func restoreFolderAssignments(_ assignments: [(fileId: String, folderId: UUID?)]) async {
        var failed = 0
        for (fileId, folderId) in assignments {
            do {
                try await supabaseService.moveFileToFolder(fileId: fileId, folderId: folderId)
                if let index = files.firstIndex(where: { $0.id == fileId }) {
                    files[index].folderId = folderId
                }
            } catch {
                failed += 1
                let appError = ErrorHandlingService.mapToAppError(error)
                logError("LibraryViewModel", "Geri alma hatası", error: appError)
            }
        }

        if failed > 0 {
            errorMessage = "\(failed) dosya geri alınamadı."
        }
        await loadFoldersAndTags()
    }

    /// Drag & drop hedefi: sürüklenen dosya ID'lerini klasöre taşır.
    func moveFilesByIds(_ fileIds: [String], to folder: Folder?) async {
        for fileId in fileIds {
            if let file = files.first(where: { $0.id == fileId }) {
                await moveFile(file, to: folder)
            }
        }
    }
}
