import SwiftUI

/// Preview dialog for bookmark file import.
///
/// Shows the folder structure from the parsed HTML file with conflict
/// indicators for folders that already exist (will be merged).
///
/// ## Usage
/// ```swift
/// BookmarkImportPreview(
///     folders: parsedFolders,
///     conflicts: ["Reading List"],
///     onImport: { /* perform import */ },
///     onCancel: { /* dismiss */ }
/// )
/// ```
struct BookmarkImportPreview: View {
    let folders: [ImportedFolder]
    let conflicts: [String]
    let onImport: () -> Void
    let onCancel: () -> Void

    @State private var isImporting = false

    private var totalBookmarks: Int {
        folders.reduce(0) { $0 + $1.totalBookmarkCount }
    }

    private var totalFolders: Int {
        folders.reduce(0) { $0 + $1.totalFolderCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            folderTree
            if !conflicts.isEmpty {
                conflictWarning
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 400)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "square.and.arrow.down")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Bookmarks")
                    .font(.headline)
                Text("\(totalBookmarks) bookmarks in \(totalFolders) folders")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Folder Tree

    private var folderTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(folders) { folder in
                    FolderRow(
                        folder: folder,
                        conflicts: conflicts,
                        depth: 0,
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Conflict Warning

    private var conflictWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("\(conflicts.count) folder\(conflicts.count == 1 ? "" : "s") will be merged with existing folder\(conflicts.count == 1 ? "" : "s")")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.1))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(action: {
                isImporting = true
                onImport()
            }) {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                    Text("Importing...")
                } else {
                    Text("Import \(totalBookmarks) items")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isImporting || totalBookmarks == 0)
        }
        .padding()
    }
}

// MARK: - Folder Row

private struct FolderRow: View {
    let folder: ImportedFolder
    let conflicts: [String]
    let depth: Int

    private var isConflict: Bool {
        conflicts.contains { $0.lowercased() == folder.name.lowercased() }
    }

    private var indentation: CGFloat {
        CGFloat(depth) * 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder header
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)

                Text(folder.name)
                    .fontWeight(depth == 0 ? .medium : .regular)

                Text("(\(folder.bookmarks.count) bookmarks)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if isConflict {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Merge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, indentation + 12)
            .padding(.vertical, 6)
            .padding(.trailing, 12)
            .contentShape(Rectangle())

            // Subfolders (recursive)
            ForEach(folder.subfolders) { subfolder in
                FolderRow(
                    folder: subfolder,
                    conflicts: conflicts,
                    depth: depth + 1,
                )
            }
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    BookmarkImportPreview(
        folders: [
            ImportedFolder(
                name: "Bookmarks Bar",
                bookmarks: [
                    ImportedBookmark(url: URL.staticRequired("https://apple.com"), title: "Apple"),
                    ImportedBookmark(url: URL.staticRequired("https://google.com"), title: "Google"),
                ],
                subfolders: [
                    ImportedFolder(
                        name: "Work",
                        bookmarks: [
                            ImportedBookmark(url: URL.staticRequired("https://github.com"), title: "GitHub"),
                        ],
                    ),
                    ImportedFolder(
                        name: "Personal",
                        bookmarks: [],
                    ),
                ],
                isFavoritesFolder: true,
            ),
            ImportedFolder(
                name: "Other Bookmarks",
                bookmarks: [],
                subfolders: [
                    ImportedFolder(
                        name: "Reading List",
                        bookmarks: [
                            ImportedBookmark(url: URL.staticRequired("https://medium.com"), title: "Medium"),
                        ],
                    ),
                ],
            ),
        ],
        conflicts: ["Reading List"],
        onImport: {},
        onCancel: {},
    )
}
