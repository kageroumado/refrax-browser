import SwiftUI

/// Sheet for creating a new space with customization options.
struct CreateSpaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WindowState.self) private var windowState
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(BrowserState.self) private var browserState

    @State private var name = ""
    @State private var icon = "briefcase.fill"
    @State private var selectedColor: Color = .blue
    @State private var dataStoreMode: DataStoreMode = .global

    // Security settings
    @State private var isLockEnabled = false
    @State private var lockTimeout: LockTimeout = .fiveMinutes

    // Download settings
    @State private var customDownloadPath: String?
    @State private var downloadColorTag: FinderColorTag = .none

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
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
                    SpaceIdentitySection(name: $name, icon: $icon, color: $selectedColor)
                    SpaceAppearanceSection(icon: $icon, color: $selectedColor)
                    SpaceDataStorageSection(dataStoreMode: $dataStoreMode)
                    SpaceSecuritySection(isLockEnabled: $isLockEnabled, lockTimeout: $lockTimeout)
                    SpaceDownloadsSection(
                        customDownloadPath: $customDownloadPath,
                        downloadColorTag: $downloadColorTag,
                        defaultDownloadPath: defaultDownloadPath,
                    )
                }
                .padding(.horizontal, SpaceSheetLayout.horizontalPadding)
                .padding(.vertical, SpaceSheetLayout.verticalPadding)
                .onChange(of: dataStoreMode) { _, newValue in
                    if case .private = newValue {
                        isLockEnabled = true
                        lockTimeout = .onLoseFocus
                    }
                }
            }

            SpaceSheetFooter(
                primaryTitle: "Create Space",
                isValid: isValid,
                onCancel: { dismiss() },
                onPrimary: { createSpace() },
            )
        }
        .frame(width: SpaceSheetLayout.sheetWidth)
    }

    // MARK: - Header

    private var header: some View {
        Text("Create Space")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SpaceSheetLayout.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func createSpace() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedIcon = icon.trimmingCharacters(in: .whitespaces)

        let space = spaceManager.createSpace(
            name: trimmedName,
            color: selectedColor,
            iconName: trimmedIcon.isEmpty ? "briefcase.fill" : trimmedIcon,
            dataStoreMode: dataStoreMode,
        )

        // Apply download settings
        space.customDownloadPath = customDownloadPath
        space.downloadColorTag = downloadColorTag == .none ? nil : downloadColorTag.rawValue

        // Apply security settings
        space.isLockEnabled = isLockEnabled
        space.lockTimeoutOverride = lockTimeout.isDefault ? nil : lockTimeout.rawValue

        // Mark as unlocked so user can use it immediately (will lock after timeout)
        if isLockEnabled {
            browserState.spaceLockManager.markUnlockedForNewSpace(space: space)
        }

        // Newly created space is never locked, use sync version
        spaceManager.switchToSpaceSync(space, for: windowState)

        dismiss()
    }
}
