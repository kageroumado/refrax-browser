import SwiftUI

/// Sheet for editing an existing space's properties.
struct EditSpaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(BrowserState.self) private var browserState

    let space: Space

    @State private var spaceName: String = ""
    @State private var selectedColor: Color = .blue
    @State private var iconName: String = ""
    @State private var customDownloadPath: String?
    @State private var downloadColorTag: FinderColorTag = .none

    // Security settings
    @State private var isLockEnabled: Bool
    @State private var lockTimeout: LockTimeout

    /// Whether lock was originally enabled when the sheet opened.
    private let wasLockEnabledOriginally: Bool

    init(space: Space) {
        self.space = space
        _spaceName = State(initialValue: space.name)
        _selectedColor = State(initialValue: space.color)
        _iconName = State(initialValue: space.iconName)
        _customDownloadPath = State(initialValue: space.customDownloadPath)
        _downloadColorTag = State(initialValue: FinderColorTag.from(space.downloadColorTag))
        _isLockEnabled = State(initialValue: space.isLockEnabled)
        _lockTimeout = State(initialValue: LockTimeout(seconds: space.lockTimeoutOverride))
        self.wasLockEnabledOriginally = space.isLockEnabled
    }

    private var isValid: Bool {
        !spaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var defaultDownloadPath: String {
        let path = browserState.downloadManager.downloadDirectory.path
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: SpaceSheetLayout.sectionSpacing) {
                    SpaceIdentitySection(name: $spaceName, icon: $iconName, color: $selectedColor)
                    SpaceAppearanceSection(icon: $iconName, color: $selectedColor)
                    SpaceDataStorageInfoSection(dataStoreMode: space.dataStoreMode)
                    securitySection
                    SpaceDownloadsSection(
                        customDownloadPath: $customDownloadPath,
                        downloadColorTag: $downloadColorTag,
                        defaultDownloadPath: defaultDownloadPath,
                        existingPath: space.customDownloadPath,
                    )
                }
                .padding(.horizontal, SpaceSheetLayout.horizontalPadding)
                .padding(.vertical, SpaceSheetLayout.verticalPadding)
            }

            SpaceSheetFooter(
                primaryTitle: "Save",
                isValid: isValid,
                onCancel: { dismiss() },
                onPrimary: { saveSpace() },
            )
        }
        .frame(width: SpaceSheetLayout.sheetWidth)
    }

    // MARK: - Header

    private var header: some View {
        Text("Edit Space")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SpaceSheetLayout.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    // MARK: - Security Section

    /// Custom binding for lock toggle that requires authentication when disabling.
    private var lockEnabledBinding: Binding<Bool> {
        Binding(
            get: { isLockEnabled },
            set: { newValue in
                if newValue {
                    // Enabling lock doesn't require auth
                    isLockEnabled = true
                } else if wasLockEnabledOriginally {
                    // Disabling lock requires auth if it was originally enabled
                    Task {
                        let result = await browserState.spaceLockManager
                            .authenticateToModifyLockSettings(for: space)
                        if case .success = result {
                            isLockEnabled = false
                        }
                    }
                } else {
                    // Lock wasn't originally enabled, so no auth needed to disable
                    isLockEnabled = false
                }
            },
        )
    }

    private var securitySection: some View {
        SpaceSectionContainer(header: "Security") {
            Toggle("Require Authentication", isOn: lockEnabledBinding)

            if isLockEnabled {
                Picker("Re-lock after", selection: $lockTimeout) {
                    ForEach(LockTimeout.allCases) { timeout in
                        Text(timeout.displayName).tag(timeout)
                    }
                }
            }

            SpaceSectionFooter {
                Text("Use Touch ID or password to access this space.")

                if isLockEnabled {
                    Text("This feature provides casual privacy protection. It is not designed to protect against forensic analysis or determined attempts to access browser data.")
                }
            }
        }
    }

    // MARK: - Actions

    private func saveSpace() {
        let trimmedName = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIcon = iconName.trimmingCharacters(in: .whitespacesAndNewlines)

        spaceManager.updateSpace(
            space,
            name: trimmedName,
            iconName: trimmedIcon.isEmpty ? "briefcase.fill" : trimmedIcon,
            color: selectedColor,
        )

        // Update download settings directly
        space.customDownloadPath = customDownloadPath
        space.downloadColorTag = downloadColorTag == .none ? nil : downloadColorTag.rawValue

        // Update security settings
        space.isLockEnabled = isLockEnabled
        space.lockTimeoutOverride = lockTimeout.isDefault ? nil : lockTimeout.rawValue

        dismiss()
    }
}
