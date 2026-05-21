import SwiftData
import SwiftUI

/// Sheet for creating a new bookmark with full configuration options.
///
/// Provides fields for:
/// - URL (required)
/// - Title (auto-filled from URL)
/// - Folder selection
/// - Tags
/// - Space assignment
/// - Favorite mode
///
/// ✅ Uses @Query for reactive folder list
struct CreateBookmarkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext
    
    let selectedFolder: BookmarkFolder?
    
    @State private var urlString = ""
    @State private var title = ""
    @State private var selectedFolderID: UUID?
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var selectedSpaceID: UUID?
    @State private var isFavorite = false
    @State private var favoriteMode: FavoriteMode = .shortcut
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Form
            ScrollView {
                form
                    .padding(20)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 480, height: 540)
        .onAppear {
            selectedFolderID = selectedFolder?.id
        }
        .alert("Invalid URL", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("New Bookmark")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }
    
    // MARK: - Form
    
    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            // URL
            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.headline)
                
                TextField("https://example.com", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        fetchTitleFromURL()
                    }
            }
            
            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.headline)
                
                TextField("Page Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            
            Divider()
            
            // Folder
            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(.headline)
                
                FolderPicker(selection: $selectedFolderID)
            }
            
            // Tags
            VStack(alignment: .leading, spacing: 6) {
                Text("Tags")
                    .font(.headline)
                
                // Tag input
                HStack {
                    TextField("Add tag...", text: $tagInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addTag()
                        }
                    
                    Button("Add") {
                        addTag()
                    }
                    .disabled(tagInput.isEmpty)
                }
                
                // Tag list
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                TagChip(tag: tag) {
                                    removeTag(tag)
                                }
                            }
                        }
                    }
                }
            }
            
            // Space
            if tabManager.hasMultipleSpaces {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Space")
                        .font(.headline)
                    
                    Picker("Space", selection: $selectedSpaceID) {
                        Text("All Spaces")
                            .tag(nil as UUID?)
                        
                        ForEach(tabManager.state.spaces) { space in
                            HStack {
                                Text(space.iconName)
                                Text(space.name)
                            }
                            .tag(space.id as UUID?)
                        }
                    }
                    .labelsHidden()
                }
            }
            
            Divider()
            
            // Favorites
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Add to Favorites", isOn: $isFavorite)
                    .font(.headline)
                
                if isFavorite {
                    Picker("Favorite Mode", selection: $favoriteMode) {
                        Label("Shortcut", systemImage: "link")
                            .tag(FavoriteMode.shortcut)
                        Label("Live Tab", systemImage: "pin.fill")
                            .tag(FavoriteMode.liveFavorite)
                    }
                    .pickerStyle(.segmented)
                    
                    Text(favoriteModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button("Create") {
                createBookmark()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var isValid: Bool {
        !urlString.isEmpty && URL(string: urlString) != nil
    }
    
    private var favoriteModeDescription: String {
        switch favoriteMode {
        case .shortcut:
            "Opens URL in current tab when clicked"
        case .liveFavorite:
            "Creates a persistent pinned tab"
        }
    }
    
    // MARK: - Actions
    
    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        
        tags.append(trimmed)
        tagInput = ""
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    private func fetchTitleFromURL() {
        // Auto-fill title from URL
        if title.isEmpty, let url = URL(string: urlString) {
            title = url.host ?? "Untitled"
        }
    }
    
    private func createBookmark() {
        guard let url = URL(string: urlString) else {
            errorMessage = "Please enter a valid URL"
            showError = true
            return
        }
        
        // Get folder if selected
        let folder: BookmarkFolder?
        if let folderID = selectedFolderID {
            let descriptor = FetchDescriptor<BookmarkFolder>(
                predicate: #Predicate { $0.id == folderID },
            )
            folder = try? modelContext.fetch(descriptor).first
        } else {
            folder = nil
        }
        
        // Create bookmark
        let bookmark = bookmarksManager.createBookmark(
            url: url,
            title: title.isEmpty ? nil : title,
            folder: folder,
            isFavorite: isFavorite,
            favoriteMode: favoriteMode,
            tags: tags,
            spaceID: selectedSpaceID,
        )
        // Load favicon asynchronously (no WebPage available)
        Task {
            if let faviconData = try? await FaviconService.fetchFavicon(for: url) {
                bookmark.faviconData = faviconData
            }
        }
        
        dismiss()
    }
}

// MARK: - Folder Picker (Reactive with @Query)

private struct FolderPicker: View {
    @Binding var selection: UUID?
    
    @Query(
        filter: #Predicate<BookmarkFolder> { $0.parentFolderID == nil },
        sort: \BookmarkFolder.position,
    )
    private var rootFolders: [BookmarkFolder]
    
    var body: some View {
        Picker("Folder", selection: $selection) {
            Text("None")
                .tag(nil as UUID?)
            
            ForEach(rootFolders) { folder in
                FolderPickerNode(folder: folder)
            }
        }
        .labelsHidden()
    }
}

private struct FolderPickerNode: View {
    let folder: BookmarkFolder
    let depth: Int
    
    @Query private var subfolders: [BookmarkFolder]
    
    init(folder: BookmarkFolder, depth: Int = 0) {
        self.folder = folder
        self.depth = depth
        
        let folderID = folder.id
        _subfolders = Query(
            filter: #Predicate<BookmarkFolder> { $0.parentFolderID == folderID },
            sort: \BookmarkFolder.position,
        )
    }
    
    var body: some View {
        Group {
            HStack {
                // Indentation
                if depth > 0 {
                    ForEach(0 ..< depth, id: \.self) { _ in
                        Text("    ")
                    }
                }
                
                // Icon
                if let customIcon = folder.customIcon {
                    customIcon.view(size: 14)
                } else {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(folder.swiftUIColor)
                }
                
                Text(folder.name)
            }
            .tag(folder.id as UUID?)
            
            // Subfolders
            ForEach(subfolders) { subfolder in
                FolderPickerNode(folder: subfolder, depth: depth + 1)
            }
        }
    }
}

// MARK: - Tag Chip

private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.appAccentColor.opacity(0.15))
        .foregroundStyle(Color.appAccentColor)
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    CreateBookmarkSheet(selectedFolder: nil)
}
