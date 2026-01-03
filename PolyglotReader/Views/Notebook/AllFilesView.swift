import SwiftUI

struct AllFilesView: View {
    let files: [FileAnnotationInfo]
    let onSelectFile: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchQuery = ""

    private var filteredFiles: [FileAnnotationInfo] {
        if searchQuery.isEmpty {
            return files
        }
        return files.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.medium))
                            Text("Geri")
                        }
                        .foregroundStyle(.indigo)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 36, height: 36)

                        Image(systemName: "folder.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tüm Dosyalar")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text("\(files.count) dosya")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .background(Color(.systemBackground))

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Dosya ara...", text: $searchQuery)
                    .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Files List
            if filteredFiles.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Dosya bulunamadı")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredFiles) { file in
                            FileRow(file: file)
                                .onTapGesture {
                                    onSelectFile(file.id)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct FileRow: View {
    let file: FileAnnotationInfo

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text("\(file.count) not")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    AllFilesView(
        files: [
            FileAnnotationInfo(id: "1", name: "Test File 1.pdf", count: 25),
            FileAnnotationInfo(id: "2", name: "Another Document.pdf", count: 15)
        ],
        onSelectFile: { _ in },
        onDismiss: {}
    )
}
