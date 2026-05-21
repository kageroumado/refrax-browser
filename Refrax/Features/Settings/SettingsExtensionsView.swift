import SwiftUI
import UniformTypeIdentifiers

// MARK: - Extension Settings

/// Custom UTType for Chrome extension files.
private extension UTType {
    static let crx = UTType(filenameExtension: "crx") ?? .data
    static let xpi = UTType(filenameExtension: "xpi") ?? .data
}

struct ExtensionSettingsView: View {
    @Environment(ExtensionManager.self) private var extensionManager
    let highlightedItemId: String?

    @State private var showFolderImporter = false
    @State private var showArchiveImporter = false
    @State private var showGallery = false
    @State private var selectedExtension: InstalledExtension?
    @State private var isLoadingInstall = false
    @State private var installError: String?
    @State private var showInstallErrorAlert = false

    var body: some View {
        Form {
            Section {
                extensionsList
            } header: {
                Text("Installed Extensions")
            } footer: {
                Text("Extensions can add features to your browser. Only install extensions from sources you trust.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .highlightable(id: "extensions.installed", highlightedItemId: highlightedItemId)

            Section {
                Button {
                    showGallery = true
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                        Text("Browse Extension Gallery…")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Browse popular Chrome and Firefox extensions that work with Refrax.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .highlightable(id: "extensions.gallery", highlightedItemId: highlightedItemId)

            Section {
                Button {
                    showFolderImporter = true
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Install from Folder…")
                    }
                }

                Button {
                    showArchiveImporter = true
                } label: {
                    HStack {
                        Image(systemName: "archivebox")
                        Text("Install from Archive (.crx/.xpi)…")
                    }
                }
            }
            .highlightable(id: "extensions.install", highlightedItemId: highlightedItemId)
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { result in
            handleFolderImport(result)
        }
        .fileImporter(
            isPresented: $showArchiveImporter,
            allowedContentTypes: [.crx, .xpi, .zip],
            allowsMultipleSelection: false,
        ) { result in
            handleArchiveImport(result)
        }
        .sheet(item: $selectedExtension) { ext in
            ExtensionDetailSheet(extension: ext)
        }
        .sheet(isPresented: $showGallery) {
            ExtensionGalleryView()
        }
        .alert("Installation Failed", isPresented: $showInstallErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installError ?? "Unknown error")
        }
    }

    // MARK: - Extensions List

    @ViewBuilder
    private var extensionsList: some View {
        if extensionManager.installedExtensions.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No extensions installed")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                Spacer()
            }
        } else {
            ForEach(extensionManager.installedExtensions) { ext in
                ExtensionRow(
                    extension_: ext,
                    onSelect: {
                        selectedExtension = ext
                    },
                )
            }
        }
    }

    // MARK: - Actions

    private func handleFolderImport(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }

            isLoadingInstall = true
            Task {
                do {
                    let didAccessScope = url.startAccessingSecurityScopedResource()
                    defer {
                        if didAccessScope {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    try await extensionManager.installFromFolder(url)
                } catch {
                    installError = error.localizedDescription
                    showInstallErrorAlert = true
                }
                isLoadingInstall = false
            }

        case let .failure(error):
            installError = error.localizedDescription
            showInstallErrorAlert = true
        }
    }

    private func handleArchiveImport(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }

            isLoadingInstall = true
            Task {
                do {
                    let didAccessScope = url.startAccessingSecurityScopedResource()
                    defer {
                        if didAccessScope {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    try await extensionManager.installFromArchive(url)
                } catch {
                    installError = error.localizedDescription
                    showInstallErrorAlert = true
                }
                isLoadingInstall = false
            }

        case let .failure(error):
            installError = error.localizedDescription
            showInstallErrorAlert = true
        }
    }
}

// MARK: - Extension Row

private struct ExtensionRow: View {
    let extension_: InstalledExtension
    let onSelect: () -> Void

    @Environment(ExtensionManager.self) private var extensionManager
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                extensionIcon
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(extension_.displayName)
                            .font(.body)
                            .fontWeight(.medium)

                        if !extension_.isEnabled {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text("Version \(extension_.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.appAccentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let iconData = extension_.iconData, let nsImage = NSImage(data: iconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.appAccentColor.opacity(0.15))
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - Extension Detail Sheet

private struct ExtensionDetailSheet: View {
    let `extension`: InstalledExtension

    @Environment(ExtensionManager.self) private var extensionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showUninstallAlert = false
    @State private var isUninstalling = false
    @State private var metrics: ResourceMetrics?
    @State private var showErrorConsole = false

    /// Current state of the extension, looked up live so toggles reflect edits.
    /// Falls back to the captured value so the sheet never becomes empty after uninstall.
    private var extension_: InstalledExtension {
        extensionManager.installedExtensions.first { $0.id == `extension`.id } ?? `extension`
    }

    private var isInstalled: Bool {
        extensionManager.installedExtensions.contains { $0.id == `extension`.id }
    }

    private var extensionErrors: [ExtensionRecoveryManager.ErrorLogEntry] {
        extensionManager.recoveryManager.errors(for: extension_)
    }

    var body: some View {
        NavigationStack {
            extensionDetailContent(extension_)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    @ViewBuilder
    private func extensionDetailContent(_ ext: InstalledExtension) -> some View {
        Form {
            // Header section — always renders, uses captured data that is always present.
            Section {
                HStack(spacing: 16) {
                    extensionIcon(for: ext)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(ext.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Version \(ext.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let description = ext.description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
            }

            // Safari Web Extension compatibility disclaimer.
            if case .bundled = ext.source {
                compatibilitySection(for: ext)
            }

            if !isInstalled {
                Section {
                    Label(
                        "This extension is no longer installed.",
                        systemImage: "exclamationmark.circle",
                    )
                    .foregroundStyle(.secondary)
                }
            }

            // Enable/Disable toggle
            Section {
                Toggle("Enabled", isOn: enabledBinding(for: ext))
                    .disabled(!isInstalled)
            }

            // Private mode
            Section {
                Toggle("Allow in Private Mode", isOn: privateBinding(for: ext))
                    .disabled(!isInstalled)
            } footer: {
                Text("Extensions are not allowed in private browsing spaces by default for privacy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Update behavior
            Section("Updates") {
                Picker("Update behavior", selection: updateBehaviorBinding(for: ext)) {
                    ForEach(UpdateBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                .disabled(!isInstalled)
            }

            // Permissions (read-only for now)
            if !ext.grantedPermissions.isEmpty || !ext.grantedMatchPatterns.isEmpty {
                Section("Permissions") {
                    ForEach(Array(ext.grantedPermissions.keys.sorted()), id: \.self) { permission in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(permission)
                            Spacer()
                        }
                    }

                    ForEach(Array(ext.grantedMatchPatterns.keys.sorted()), id: \.self) { pattern in
                        HStack {
                            Image(systemName: "globe")
                                .foregroundStyle(.blue)
                            Text(pattern)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                    }
                }
            }

            // Per-site disable list
            if !ext.disabledOnDomains.isEmpty {
                Section("Disabled on Sites") {
                    ForEach(Array(ext.disabledOnDomains.sorted()), id: \.self) { domain in
                        Text(domain)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            // Source info
            Section("Source") {
                HStack {
                    Text("Installed from")
                    Spacer()
                    Text(ext.source.displayName)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Manifest version")
                    Spacer()
                    Text(String(format: "%.0f", ext.manifestVersion))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Installed")
                    Spacer()
                    Text(ext.installedAt, style: .date)
                        .foregroundStyle(.secondary)
                }
            }

            // Resource usage
            if ext.isEnabled {
                resourceUsageSection
            }

            // Error console
            if !extensionErrors.isEmpty {
                errorConsoleSection(for: ext)
            }

            // Developer tools (debug builds only)
            #if DEBUG
                developerSection(for: ext)
            #endif

            // Uninstall
            if isInstalled {
                Section {
                    Button(role: .destructive) {
                        showUninstallAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            if isUninstalling {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Uninstall Extension")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isUninstalling)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ext.displayName)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .alert("Uninstall Extension?", isPresented: $showUninstallAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                uninstallExtension(ext)
            }
        } message: {
            Text("This will remove \"\(ext.displayName)\" and all its data. This action cannot be undone.")
        }
        .task(id: ext.id) {
            // Notify monitor that UI is visible for efficient polling
            await extensionManager.setResourceMonitorUIVisibility(true)

            // Load metrics initially and refresh every 5 seconds
            while !Task.isCancelled {
                loadMetrics(for: ext)
                try? await Task.sleep(for: .seconds(5))
            }

            // Notify monitor that UI is no longer visible
            await extensionManager.setResourceMonitorUIVisibility(false)
        }
    }

    @ViewBuilder
    private func extensionIcon(for ext: InstalledExtension) -> some View {
        if let iconData = ext.iconData, let nsImage = NSImage(data: iconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appAccentColor.opacity(0.15))
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Bindings

    private func enabledBinding(for ext: InstalledExtension) -> Binding<Bool> {
        Binding(
            get: { ext.isEnabled },
            set: { newValue in
                Task {
                    do {
                        if newValue {
                            try await extensionManager.enable(ext)
                        } else {
                            try await extensionManager.disable(ext)
                        }
                    } catch {
                        Logger.error("Failed to toggle extension: \(error)", category: Logger.extensions)
                    }
                }
            },
        )
    }

    private func privateBinding(for ext: InstalledExtension) -> Binding<Bool> {
        Binding(
            get: { ext.allowedInPrivateMode },
            set: { newValue in
                extensionManager.setPrivateMode(newValue, for: ext)
            },
        )
    }

    private func updateBehaviorBinding(for ext: InstalledExtension) -> Binding<UpdateBehavior> {
        Binding(
            get: { ext.updateBehavior },
            set: { newValue in
                extensionManager.setUpdateBehavior(newValue, for: ext)
            },
        )
    }

    // MARK: - Actions

    private func uninstallExtension(_ ext: InstalledExtension) {
        isUninstalling = true
        Task {
            do {
                try await extensionManager.uninstall(ext)
                dismiss()
            } catch {
                Logger.error("Failed to uninstall extension: \(error)", category: Logger.extensions)
            }
            isUninstalling = false
        }
    }

    private func loadMetrics(for ext: InstalledExtension) {
        Task {
            metrics = await extensionManager.resourceMetrics(for: ext)
        }
    }

    private func errorColor(for severity: ExtensionRecoveryManager.ErrorLogEntry.Severity) -> Color {
        switch severity {
        case .warning: .yellow
        case .error: .red
        case .crash: .orange
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private func compatibilitySection(for ext: InstalledExtension) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Compatibility", systemImage: "info.circle")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                Text(compatibilityMessage(for: ext))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private func compatibilityMessage(for ext: InstalledExtension) -> AttributedString {
        let raw: String
        if isICloudPasswords(ext) {
            raw = """
            **iCloud Passwords** requires private Apple APIs available only to Safari. \
            In Refrax, it may show saved usernames but **cannot autofill passwords or passkeys**, \
            and there is no way for us to enable this — Apple restricts the APIs to Safari's Team ID and Bundle ID.
            """
        } else {
            raw = """
            Safari Web Extensions like this one are designed for Safari's sandbox. \
            Refrax can load them, but some features — especially **iCloud Passwords autofill** and **passkey support** — \
            require private system APIs that Apple restricts to Safari's Team ID and Bundle ID. \
            These features will not work in Refrax, and there is no way for us to enable them. \
            Username suggestions may still work in some cases.
            """
        }

        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    private func isICloudPasswords(_ ext: InstalledExtension) -> Bool {
        if case let .bundled(name) = ext.source,
           name.localizedCaseInsensitiveContains("icloud")
               && name.localizedCaseInsensitiveContains("password") {
            return true
        }
        return ext.displayName.localizedCaseInsensitiveContains("iCloud Passwords")
    }

    @ViewBuilder
    private var resourceUsageSection: some View {
        Section {
            if let metrics {
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundStyle(.blue)
                    Text("Memory")
                    Spacer()
                    Text(metrics.formattedMemory)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(.orange)
                    Text("CPU")
                    Spacer()
                    Text(metrics.formattedCPU)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "network")
                        .foregroundStyle(.green)
                    Text("Network (req/min)")
                    Spacer()
                    Text("\(metrics.networkRequestsPerMinute)")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading metrics…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Resource Usage")
        } footer: {
            if let metrics {
                Text("Peak: \(metrics.formattedPeakMemory) memory, \(metrics.formattedPeakCPU) CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if DEBUG
        @ViewBuilder
        private func developerSection(for ext: InstalledExtension) -> some View {
            Section {
                Button {
                    extensionManager.inspectExtension(ext)
                } label: {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(.orange)
                        Text("Inspect Extension")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!ext.isEnabled)
            } header: {
                Text("Developer")
            } footer: {
                Text("Opens Web Inspector for the extension's background page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    #endif

    @ViewBuilder
    private func errorConsoleSection(for ext: InstalledExtension) -> some View {
        Section {
            ForEach(Array(extensionErrors.prefix(5))) { error in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: error.severityIcon)
                        .foregroundStyle(errorColor(for: error.severity))
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.error)
                            .font(.caption)
                            .lineLimit(2)

                        Text(error.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if extensionErrors.count > 5 {
                Button("View All Errors (\(extensionErrors.count))") {
                    showErrorConsole = true
                }
                .font(.caption)
            }

            Button("Clear Errors", role: .destructive) {
                extensionManager.recoveryManager.clearErrors(for: ext)
            }
            .font(.caption)
        } header: {
            Text("Recent Errors")
        }
    }
}

// MARK: - Supporting Extensions

private extension UpdateBehavior {
    var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .notify: "Notify before updating"
        case .manual: "Manual only"
        }
    }
}

private extension ExtensionSource {
    var displayName: String {
        switch self {
        case let .localFolder(url):
            "Local folder: \(url.lastPathComponent)"
        case .crxFile:
            "Chrome extension file"
        case .xpiFile:
            "Firefox extension file"
        case .chromeWebStore:
            "Chrome Web Store"
        case .firefoxAddons:
            "Firefox Add-ons"
        case .refraxGallery:
            "Refrax Gallery"
        case .bundled:
            "Bundled with Refrax"
        }
    }
}
