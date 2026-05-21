import SwiftData
import SwiftUI

/// Sheet for creating a new bookmark folder.
///
/// Provides fields for:
/// - Name (required)
/// - Color
/// - Icon (SF Symbol or emoji)
/// - Parent folder (for nesting)
struct CreateFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(\.modelContext) private var modelContext
    
    let parentFolder: BookmarkFolder?
    
    @State private var name = ""
    @State private var selectedColor = Color.blue
    @State private var iconInput = ""
    @State private var useCustomIcon = false
    @State private var selectedParentID: UUID?
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Common colors for folders (matching Reminders aesthetic)
    private let commonColors: [(name: String, color: Color)] = [
        ("Blue", .blue),
        ("Purple", .purple),
        ("Pink", .pink),
        ("Red", .red),
        ("Orange", .orange),
        ("Yellow", .yellow),
        ("Green", .green),
        ("Teal", .cyan),
        ("Indigo", .indigo),
        ("Gray", .gray),
    ]
    
    // Common folder icons
    private let commonIcons = ["📁", "💼", "🏠", "📚", "🎨", "🔬", "💻", "🎮", "✈️", "🏋️"]
    
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
        .frame(width: 400, height: 480)
        .onAppear {
            selectedParentID = parentFolder?.id
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("New Folder")
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
            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.headline)
                
                TextField("Folder Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            
            Divider()
            
            // Icon
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Custom Icon", isOn: $useCustomIcon)
                    .font(.headline)
                
                if useCustomIcon {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose Icon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // Common icons grid
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
                            ForEach(commonIcons, id: \.self) { icon in
                                Button(action: {
                                    iconInput = icon
                                }) {
                                    Text(icon)
                                        .font(.title)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            iconInput == icon
                                                ? Color.appAccentColor.opacity(0.2)
                                                : Color.clear,
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Custom input
                        TextField("Or enter custom emoji", text: $iconInput)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose Color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                            ForEach(commonColors, id: \.name) { colorOption in
                                Button(action: {
                                    selectedColor = colorOption.color
                                }) {
                                    Circle()
                                        .fill(colorOption.color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    Color.primary.opacity(selectedColor == colorOption.color ? 0.5 : 0),
                                                    lineWidth: 3,
                                                ),
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Parent folder
            VStack(alignment: .leading, spacing: 6) {
                Text("Parent Folder")
                    .font(.headline)
                
                FolderPicker(selection: $selectedParentID, maxDepth: 2)
                
                if let parent = selectedParent, parent.depth >= 2 {
                    Text("Cannot nest more than 3 levels deep")
                        .font(.caption)
                        .foregroundStyle(.red)
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
                createFolder()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        
        // Check depth limit
        if let parent = selectedParent, parent.depth >= 2 {
            return false
        }
        
        return true
    }
    
    private var selectedParent: BookmarkFolder? {
        guard let parentID = selectedParentID else { return nil }
        
        let descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.id == parentID },
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    // MARK: - Actions
    
    private func createFolder() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a folder name"
            showError = true
            return
        }
        
        let colorHex = selectedColor.components.taggedString
        let iconName: String? = useCustomIcon && !iconInput.isEmpty ? iconInput : nil
        
        do {
            _ = try bookmarksManager.createFolder(
                name: trimmedName,
                color: colorHex,
                iconName: iconName,
                parent: selectedParent,
            )
            
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Folder Picker with Depth Limit

private struct FolderPicker: View {
    @Environment(BookmarksManager.self) private var bookmarksManager
    
    @Binding var selection: UUID?
    let maxDepth: Int
    
    var body: some View {
        Picker("Parent", selection: $selection) {
            Text("None (Root Level)")
                .tag(nil as UUID?)
            
            ForEach(availableFolders) { folder in
                FolderPickerNode(folder: folder)
            }
        }
        .labelsHidden()
    }
    
    private var availableFolders: [BookmarkFolder] {
        bookmarksManager.rootFolders().filter { $0.depth < maxDepth }
    }
}

private struct FolderPickerNode: View {
    @Environment(BookmarksManager.self) private var bookmarksManager
    
    let folder: BookmarkFolder
    let depth: Int
    
    init(folder: BookmarkFolder, depth: Int = 0) {
        self.folder = folder
        self.depth = depth
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
            
            // Subfolders (if not at max depth)
            if folder.depth < 2 {
                ForEach(subfolders) { subfolder in
                    FolderPickerNode(folder: subfolder, depth: depth + 1)
                }
            }
        }
    }
    
    private var subfolders: [BookmarkFolder] {
        bookmarksManager.subfolders(of: folder)
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    CreateFolderSheet(parentFolder: nil)
}
