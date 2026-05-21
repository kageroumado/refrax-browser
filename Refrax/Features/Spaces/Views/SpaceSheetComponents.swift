import SwiftUI

// MARK: - Layout Constants

enum SpaceSheetLayout {
    static let sheetWidth: CGFloat = 512
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 20
    static let previewSize: CGFloat = 48
    static let previewCornerRadius: CGFloat = 10
    static let previewIconSize: CGFloat = 24
}

// MARK: - Section Container

/// A container that wraps content in a Form to get proper macOS control styling.
/// Form provides section backgrounds and proper Toggle/Picker rendering.
struct SpaceSectionContainer<Content: View>: View {
    let header: String?
    @ViewBuilder let content: Content

    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        Form {
            Section {
                content
            } header: {
                if let header {
                    Text(header)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, -20) // Remove Form's horizontal padding
        .padding(.vertical, -20) // Remove Form's vertical padding
    }
}

/// A simple visual container with section background styling.
/// Use for custom layouts that don't need Form's control styling.
struct SpaceSectionBox<Content: View>: View {
    let header: String?
    @ViewBuilder let content: Content

    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Section Footer

/// A footer text for sections with secondary styling.
struct SpaceSectionFooter<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    init(_ text: String) where Content == Text {
        self.content = Text(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Space Preview Icon

/// A preview icon showing the space's icon and color.
struct SpacePreviewIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SpaceSheetLayout.previewCornerRadius)
                .fill(color.opacity(0.2))
                .frame(width: SpaceSheetLayout.previewSize, height: SpaceSheetLayout.previewSize)

            if isEmoji(icon) {
                Text(icon)
                    .font(.system(size: SpaceSheetLayout.previewIconSize))
            } else {
                Image(systemName: icon)
                    .font(.system(size: SpaceSheetLayout.previewIconSize, weight: .medium))
                    .foregroundStyle(color)
            }
        }
    }

    private func isEmoji(_ string: String) -> Bool {
        guard string.count == 1, let scalar = string.unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || string.unicodeScalars.count > 1)
    }
}

// MARK: - Identity Section

/// The identity section with space name and preview icon.
struct SpaceIdentitySection: View {
    @Binding var name: String
    @Binding var icon: String
    @Binding var color: Color

    var body: some View {
        SpaceSectionBox {
            HStack(spacing: 16) {
                SpacePreviewIcon(icon: icon, color: color)

                VStack(alignment: .leading) {
                    Text("Space Name")
                        .fontWeight(.semibold)
                    TextField("", text: $name, prompt: Text("e.g., Work, Personal, Research"))
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 300, alignment: .leading)

                Spacer()
            }
        }
    }
}

// MARK: - Appearance Section

/// The appearance section with icon and color pickers.
struct SpaceAppearanceSection: View {
    @Binding var icon: String
    @Binding var color: Color

    var body: some View {
        SpaceSectionContainer(header: "Appearance") {
            IconPicker(selectedIcon: $icon, accentColor: color)

            InlineColorPicker(selectedColor: $color)
        }
    }
}

// MARK: - Downloads Section

/// The downloads section with folder picker and color tag.
struct SpaceDownloadsSection: View {
    @Binding var customDownloadPath: String?
    @Binding var downloadColorTag: FinderColorTag
    let defaultDownloadPath: String
    let existingPath: String? // For clearing bookmarks on edit

    @State private var showDownloadFolderError = false
    @State private var downloadFolderErrorMessage = ""

    init(
        customDownloadPath: Binding<String?>,
        downloadColorTag: Binding<FinderColorTag>,
        defaultDownloadPath: String,
        existingPath: String? = nil,
    ) {
        self._customDownloadPath = customDownloadPath
        self._downloadColorTag = downloadColorTag
        self.defaultDownloadPath = defaultDownloadPath
        self.existingPath = existingPath
    }

    private var downloadPathDescription: String {
        if let path = customDownloadPath {
            "Downloaded files will be saved to “\(abbreviatedPath(path))”."
        } else {
            "Downloaded files will be saved to “\(defaultDownloadPath)”."
        }
    }

    var body: some View {
        SpaceSectionContainer(header: "Downloads") {
            // Download folder row
            LabeledContent {
                HStack(spacing: 8) {
                    if customDownloadPath != nil {
                        Button("Clear") {
                            if let existingPath {
                                DownloadFolderBookmarkManager.shared.removeBookmark(for: existingPath)
                            }
                            customDownloadPath = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Button("Choose...") {
                        selectDownloadFolder()
                    }
                }
            } label: {
                Text("Downloads folder")
                Text(downloadPathDescription)
            }

            // Color tag picker
            LabeledContent {
                Picker("", selection: $downloadColorTag) {
                    ForEach(FinderColorTag.allCases) { tag in
                        HStack(spacing: 6) {
                            if tag != .none {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 10, height: 10)
                            }
                            Text(tag.displayName)
                        }
                        .tag(tag)
                    }
                }
                .labelsHidden()
            } label: {
                Text("Color tag")
                Text("Downloaded files will be tagged with this color.")
            }
        }
        .alert("Cannot Use Folder", isPresented: $showDownloadFolderError) {
            Button("OK") {}
        } message: {
            Text(downloadFolderErrorMessage)
        }
    }

    private func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a download folder for this space"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            if FileManager.default.isWritableFile(atPath: url.path) {
                if DownloadFolderBookmarkManager.shared.createBookmark(for: url) != nil {
                    customDownloadPath = url.path
                } else {
                    showDownloadFolderError = true
                    downloadFolderErrorMessage = "Cannot access this folder. Please choose a folder you have permission to write to."
                }
            } else {
                showDownloadFolderError = true
                downloadFolderErrorMessage = "You don't have permission to write to this folder."
            }
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }
}

// MARK: - Security Section

/// The security section with authentication toggle and timeout picker.
struct SpaceSecuritySection: View {
    @Binding var isLockEnabled: Bool
    @Binding var lockTimeout: LockTimeout

    var body: some View {
        SpaceSectionContainer(header: "Security") {
            Toggle("Require authentication to access", isOn: $isLockEnabled)

            if isLockEnabled {
                Picker("Automatically lock after", selection: $lockTimeout) {
                    ForEach(LockTimeout.allCases) { timeout in
                        Text(timeout.displayName).tag(timeout)
                    }
                }
            }

            SpaceSectionFooter {
                Text("Touch ID or password will be required to access this space.")

                if isLockEnabled {
                    Text("This feature provides casual privacy protection. It is not designed to protect against forensic analysis or determined attempts to access browser data.")
                }
            }
        }
    }
}

// MARK: - Data Storage Section (Create)

/// The data storage section for creating a new space.
struct SpaceDataStorageSection: View {
    @Binding var dataStoreMode: DataStoreMode

    var body: some View {
        SpaceSectionContainer(header: "Data Storage") {
            Picker("", selection: $dataStoreMode) {
                ForEach(DataStoreMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            SpaceSectionFooter {
                Text("\(dataStoreMode.displayDescription). This cannot be changed after creation.")

                if dataStoreMode == .private {
                    Text("Private mode provides casual privacy. It does not protect against forensic analysis or prevent websites from identifying your browser through fingerprinting.")
                }
            }
        }
    }
}

// MARK: - Data Storage Info Section (Edit)

/// The data storage info section for viewing an existing space's storage mode.
struct SpaceDataStorageInfoSection: View {
    let dataStoreMode: DataStoreMode

    var body: some View {
        SpaceSectionBox(header: "Data Storage") {
            HStack(spacing: 12) {
                Image(systemName: dataStoreMode.iconName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dataStoreMode.displayName)
                        .fontWeight(.medium)

                    Text("\(dataStoreMode.displayDescription).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if dataStoreMode == .private {
                SpaceSectionFooter("Private mode provides casual privacy. It does not protect against forensic analysis or prevent websites from identifying your browser through fingerprinting.")
            }
        }
    }
}

// MARK: - Sheet Footer

/// The footer with Cancel and primary action buttons.
struct SpaceSheetFooter: View {
    let primaryTitle: String
    let isValid: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(primaryTitle, action: onPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, SpaceSheetLayout.horizontalPadding)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
