import SwiftUI

/// Recursive tree node for displaying bookmark folders
///
/// Features:
/// - Clickable folder labels that update selection
/// - Conditional disclosure chevron (only shown when subfolders exist)
/// - Context menu for folder operations
/// - Highlights selected folder
/// - Hover-to-open functionality with delay
struct FolderTreeNode: View {
    @Environment(BookmarksManager.self) private var bookmarksManager
    
    let folder: BookmarkFolder
    @Binding var selectedFolder: BookmarkFolder?
    @Binding var showFavoritesOnly: Bool
    @Binding var showCreateFolderSheet: Bool
    
    @State private var isExpanded = true
    @State private var isDropTarget = false
    @State private var hoverTask: Task<Void, any Error>?
    
    var body: some View {
        if subfolders.isEmpty {
            // No subfolders - show as clickable button without chevron
            Button(action: {
                selectedFolder = folder
                showFavoritesOnly = false
            }) {
                folderLabel
            }
            .buttonStyle(.plain)
            .foregroundStyle(selectedFolder?.id == folder.id ? Color.appAccentColor : .primary)
            .listRowBackground(isDropTarget ? Color.appAccentColor.opacity(0.1) : Color.clear)
            .contextMenu {
                folderContextMenu
            }
            .dropDestination(for: BookmarkDragItem.self) { items, _ in
                handleDrop(items: items)
            } isTargeted: { isTarget in
                handleHover(isTarget)
            }
        } else {
            // Has subfolders - show with disclosure
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(subfolders) { subfolder in
                    FolderTreeNode(
                        folder: subfolder,
                        selectedFolder: $selectedFolder,
                        showFavoritesOnly: $showFavoritesOnly,
                        showCreateFolderSheet: $showCreateFolderSheet,
                    )
                }
            } label: {
                Button(action: {
                    selectedFolder = folder
                    showFavoritesOnly = false
                }) {
                    folderLabel
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedFolder?.id == folder.id ? Color.appAccentColor : .primary)
                .contextMenu {
                    folderContextMenu
                }
            }
            .listRowBackground(isDropTarget ? Color.appAccentColor.opacity(0.1) : Color.clear)
            .dropDestination(for: BookmarkDragItem.self) { items, _ in
                handleDrop(items: items)
            } isTargeted: { isTarget in
                handleHover(isTarget)
            }
        }
    }
    
    private var folderLabel: some View {
        HStack(spacing: 8) {
            if let customIcon = folder.customIcon {
                customIcon.view(size: 16)
            } else {
                Image(systemName: "folder.fill")
                    .foregroundStyle(folder.swiftUIColor)
            }
            
            Text(folder.name)
            
            Spacer()
            
            Text("\(folder.itemCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .flash(isDropTarget)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var folderContextMenu: some View {
        Button("Rename...") {
            // TODO: Show rename sheet/dialog
        }
        
        Divider()
        
        if folder.isFavorite {
            Button("Remove from Favorites") {
                bookmarksManager.removeFolderFromFavorites(folder)
            }
        } else {
            Button("Add to Favorites") {
                bookmarksManager.addFolderToFavorites(folder)
            }
        }
        
        Divider()
        
        Button("New Subfolder...") {
            selectedFolder = folder
            showCreateFolderSheet = true
        }
        
        Divider()
        
        Button("Delete", role: .destructive) {
            bookmarksManager.deleteFolder(folder, deleteContents: false)
        }
        
        Button("Delete with Contents", role: .destructive) {
            bookmarksManager.deleteFolder(folder, deleteContents: true)
        }
    }
    
    /// Handle hover with auto-open after delay
    private func handleHover(_ isTarget: Bool) {
        isDropTarget = isTarget
        
        if isTarget {
            // Start hover timer to auto-open folder
            hoverTask = Task {
                try await Task.sleep(for: .seconds(0.75))
                
                // Open folder when hovering with bookmark
                selectedFolder = folder
                showFavoritesOnly = false
                isExpanded = true
            }
        } else {
            // Cancel hover timer
            hoverTask?.cancel()
            hoverTask = nil
        }
    }
    
    /// Handles bookmark drop on folder - moves bookmarks to this folder
    private func handleDrop(items: [BookmarkDragItem]) -> Bool {
        guard let firstItem = items.first else { return false }
        
        // Move all bookmarks to this folder
        bookmarksManager.moveBookmarks(firstItem.bookmarkIDs, to: folder)
        
        // Open the folder to show the result
        selectedFolder = folder
        showFavoritesOnly = false
        isExpanded = true
        
        return true
    }
    
    private var subfolders: [BookmarkFolder] {
        bookmarksManager.subfolders(of: folder)
    }
}
