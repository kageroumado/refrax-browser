import Foundation
import UserNotifications

/// Checks for and manages extension updates.
///
/// `ExtensionUpdateChecker` periodically checks for available updates from
/// extension sources and handles the update flow based on each extension's
/// configured `UpdateBehavior`.
///
/// ## Update Sources
///
/// - **Local folders**: No automatic updates (development mode)
/// - **CRX/XPI files**: No automatic updates (user-downloaded)
/// - **Chrome Web Store**: Checks via update manifest URL
/// - **Firefox Add-ons**: Checks via AMO API
/// - **Refrax Gallery**: Checks via curated extension metadata
///
/// ## Update Behaviors
///
/// - **Auto**: Download and apply silently in background
/// - **Notify**: Download, then show notification and wait for confirmation
/// - **Manual**: Only show badge in settings, user must trigger update
actor ExtensionUpdateChecker {
    // MARK: - Types

    /// Information about an available update.
    struct UpdateInfo: Sendable {
        let extensionID: UUID
        let currentVersion: String
        let newVersion: String
        let downloadURL: URL
        let releaseNotes: String?
    }

    /// Result of checking for updates.
    enum UpdateCheckResult: Sendable {
        case noUpdate
        case updateAvailable(UpdateInfo)
        case checkFailed(any Error)
    }

    // MARK: - Properties

    /// Extensions with available updates (not yet applied).
    private(set) var pendingUpdates: [UUID: UpdateInfo] = [:]

    /// Extensions currently being updated.
    private var updatesInProgress: Set<UUID> = []

    /// Last check timestamp per extension.
    private var lastCheckTimes: [UUID: Date] = [:]

    /// Minimum interval between update checks per extension (1 hour).
    private let minimumCheckInterval: TimeInterval = 3_600

    /// Full update check interval (24 hours).
    private let fullCheckInterval: TimeInterval = 86_400

    /// Last time a full check was performed.
    private var lastFullCheck: Date?

    /// Reference to extension manager for update application.
    private weak var extensionManager: ExtensionManager?

    // MARK: - Initialization

    init() {}

    /// Sets the extension manager reference.
    ///
    /// Must be called after initialization to enable update application.
    func setExtensionManager(_ manager: ExtensionManager) {
        extensionManager = manager
    }

    // MARK: - Update Checking

    /// Checks for updates for a single extension.
    ///
    /// - Parameter extension_: The extension to check.
    /// - Returns: The result of the update check.
    func checkForUpdate(_ extension_: InstalledExtension) async -> UpdateCheckResult {
        // Check minimum interval
        if let lastCheck = lastCheckTimes[extension_.id],
           Date().timeIntervalSince(lastCheck) < minimumCheckInterval {
            // If we already have a pending update, return it
            if let pending = pendingUpdates[extension_.id] {
                return .updateAvailable(pending)
            }
            return .noUpdate
        }

        lastCheckTimes[extension_.id] = Date()

        // Check based on source
        switch extension_.source {
        case .localFolder, .crxFile, .xpiFile:
            // No automatic updates for local/file sources
            return .noUpdate

        case let .chromeWebStore(extensionID):
            return await checkChromeWebStoreUpdate(
                extension_,
                storeID: extensionID,
            )

        case let .firefoxAddons(extensionID):
            return await checkFirefoxAddonsUpdate(
                extension_,
                addonID: extensionID,
            )

        case let .refraxGallery(extensionID):
            return await checkGalleryUpdate(
                extension_,
                galleryID: extensionID,
            )

        case let .bundled(name):
            // Bundled extensions are Firefox-based (uBlock Origin)
            // Check Firefox Add-ons for updates
            return await checkFirefoxAddonsUpdate(
                extension_,
                addonID: name,
            )
        }
    }

    /// Checks for updates for all installed extensions.
    ///
    /// - Parameter extensions: The extensions to check.
    /// - Returns: Dictionary of extension IDs to their update check results.
    func checkAllForUpdates(_ extensions: [InstalledExtension]) async -> [UUID: UpdateCheckResult] {
        var results: [UUID: UpdateCheckResult] = [:]

        await withTaskGroup(of: (UUID, UpdateCheckResult).self) { group in
            for ext in extensions {
                group.addTask {
                    let result = await self.checkForUpdate(ext)
                    return (ext.id, result)
                }
            }

            for await (id, result) in group {
                results[id] = result

                // Store pending updates
                if case let .updateAvailable(info) = result {
                    pendingUpdates[id] = info
                }
            }
        }

        return results
    }

    // MARK: - Update Application

    /// Downloads and applies an update based on the extension's update behavior.
    ///
    /// - Parameter extension_: The extension to update.
    /// - Returns: `true` if the update was applied, `false` if pending user action.
    func applyUpdate(for extension_: InstalledExtension) async throws -> Bool {
        guard let updateInfo = pendingUpdates[extension_.id] else {
            throw UpdateError.noUpdateAvailable
        }

        guard !updatesInProgress.contains(extension_.id) else {
            throw UpdateError.updateAlreadyInProgress
        }

        updatesInProgress.insert(extension_.id)
        defer { updatesInProgress.remove(extension_.id) }

        switch extension_.updateBehavior {
        case .auto:
            // Download and apply immediately
            try await downloadAndApply(extension_, updateInfo: updateInfo)
            return true

        case .notify:
            // Download first, then wait for user confirmation
            let downloadedURL = try await downloadUpdate(updateInfo)
            await storeDownloadedUpdate(extension_.id, url: downloadedURL, info: updateInfo)
            await sendUpdateNotification(extension_, updateInfo: updateInfo)
            return false

        case .manual:
            // Just mark as available, don't download
            return false
        }
    }

    /// Confirms and applies a pending update (for notify behavior).
    ///
    /// - Parameter extension_: The extension to update.
    func confirmUpdate(for extension_: InstalledExtension) async throws {
        guard let updateInfo = pendingUpdates[extension_.id] else {
            throw UpdateError.noUpdateAvailable
        }

        try await downloadAndApply(extension_, updateInfo: updateInfo)
    }

    /// Dismisses a pending update notification.
    ///
    /// - Parameter extension_: The extension to dismiss the update for.
    func dismissUpdate(for extension_: InstalledExtension) {
        pendingUpdates.removeValue(forKey: extension_.id)
    }

    // MARK: - Scheduled Update Check

    /// Checks all extensions for updates if sufficient time has elapsed.
    ///
    /// This method is designed to be called from `ScheduledTasksManager` on an hourly
    /// schedule. It tracks when the last full check occurred and only performs network
    /// requests once every 24 hours.
    ///
    /// The method is idempotent and safe to call frequently.
    func checkAllIfNeeded() async {
        // Only perform full check every 24 hours
        if let lastCheck = lastFullCheck {
            guard Date().timeIntervalSince(lastCheck) >= fullCheckInterval else { return }
        }

        guard let manager = extensionManager else {
            Logger.warning("Extension update check skipped: manager not set", category: Logger.extensions)
            return
        }

        // Check all extensions on main actor
        let extensions = await MainActor.run { manager.installedExtensions }

        guard !extensions.isEmpty else { return }

        Logger.debug("Checking \(extensions.count) extensions for updates", category: Logger.extensions)

        _ = await checkAllForUpdates(extensions)
        lastFullCheck = Date()
    }

    // MARK: - Source-Specific Checks

    /// Checks Chrome Web Store for updates.
    private func checkChromeWebStoreUpdate(
        _ extension_: InstalledExtension,
        storeID: String,
    ) async -> UpdateCheckResult {
        // Chrome Web Store update check URL
        // Uses the same protocol as Chromium browsers
        let updateURL = URL.staticRequired("https://clients2.google.com/service/update2/crx")
        guard var components = URLComponents(url: updateURL, resolvingAgainstBaseURL: false) else {
            return .checkFailed(UpdateError.invalidURL)
        }
        components.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: "120.0"),
            URLQueryItem(name: "x", value: "id=\(storeID)&v=\(extension_.version)&uc"),
        ]

        guard let requestURL = components.url else {
            return .checkFailed(UpdateError.invalidURL)
        }

        do {
            var request = URLRequest(url: requestURL)
            request.httpMethod = "HEAD"

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .checkFailed(UpdateError.invalidResponse)
            }

            // 204 = no update, 302 = redirect to new version
            if httpResponse.statusCode == 302,
               let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let downloadURL = URL(string: location) {
                // Extract version from redirect URL if possible
                let newVersion = extractVersionFromCRXURL(downloadURL) ?? "newer"

                if newVersion != extension_.version {
                    let info = UpdateInfo(
                        extensionID: extension_.id,
                        currentVersion: extension_.version,
                        newVersion: newVersion,
                        downloadURL: downloadURL,
                        releaseNotes: nil,
                    )
                    pendingUpdates[extension_.id] = info
                    return .updateAvailable(info)
                }
            }

            return .noUpdate
        } catch {
            return .checkFailed(error)
        }
    }

    /// Checks Firefox Add-ons for updates.
    private func checkFirefoxAddonsUpdate(
        _ extension_: InstalledExtension,
        addonID: String,
    ) async -> UpdateCheckResult {
        // AMO API endpoint for addon info
        guard let apiURL = URL(string: "https://addons.mozilla.org/api/v5/addons/addon/\(addonID)/") else {
            return .checkFailed(UpdateError.invalidURL)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let currentVersion = json?["current_version"] as? [String: Any],
                  let newVersion = currentVersion["version"] as? String,
                  let file = (currentVersion["files"] as? [[String: Any]])?.first,
                  let downloadURLString = file["url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                return .checkFailed(UpdateError.invalidResponse)
            }

            // Compare versions
            if compareVersions(extension_.version, newVersion) == .orderedAscending {
                let releaseNotes = (currentVersion["release_notes"] as? [String: String])?["en-US"]

                let info = UpdateInfo(
                    extensionID: extension_.id,
                    currentVersion: extension_.version,
                    newVersion: newVersion,
                    downloadURL: downloadURL,
                    releaseNotes: releaseNotes,
                )
                pendingUpdates[extension_.id] = info
                return .updateAvailable(info)
            }

            return .noUpdate
        } catch {
            return .checkFailed(error)
        }
    }

    /// Checks Refrax Gallery for updates.
    private func checkGalleryUpdate(
        _ extension_: InstalledExtension,
        galleryID: String,
    ) async -> UpdateCheckResult {
        guard let manager = extensionManager else {
            return .checkFailed(UpdateError.managerNotSet)
        }

        do {
            // Use gallery service to check for updates
            let gallery = try await MainActor.run { try manager.galleryService.fetchGallery() }

            guard let galleryExt = gallery.extensions.first(where: { $0.id == galleryID }),
                  let galleryVersion = galleryExt.version else {
                return .checkFailed(UpdateError.extensionNotInGallery)
            }

            if compareVersions(extension_.version, galleryVersion) == .orderedAscending,
               let downloadURL = await MainActor.run(body: { manager.galleryService.downloadURL(for: galleryExt) }) {
                let info = UpdateInfo(
                    extensionID: extension_.id,
                    currentVersion: extension_.version,
                    newVersion: galleryVersion,
                    downloadURL: downloadURL,
                    releaseNotes: nil,
                )
                pendingUpdates[extension_.id] = info
                return .updateAvailable(info)
            }

            return .noUpdate
        } catch {
            return .checkFailed(error)
        }
    }

    // MARK: - Private Helpers

    /// Downloads an update to a temporary location.
    private func downloadUpdate(_ info: UpdateInfo) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: info.downloadURL)

        // Move to a more permanent temp location
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("extension-update-\(info.extensionID.uuidString)")
            .appendingPathExtension(info.downloadURL.pathExtension)

        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.moveItem(at: tempURL, to: targetURL)

        return targetURL
    }

    /// Downloads and applies an update.
    private func downloadAndApply(
        _ extension_: InstalledExtension,
        updateInfo: UpdateInfo,
    ) async throws {
        let downloadedURL = try await downloadUpdate(updateInfo)

        // Apply the update via extension manager
        guard let manager = extensionManager else {
            throw UpdateError.managerNotSet
        }

        do {
            // Uninstall old version (preserving data via new install)
            try await manager.uninstall(extension_)

            // Install new version from downloaded file
            _ = try await manager.installFromArchive(downloadedURL)

            Logger.info(
                "Updated extension '\(extension_.displayName)' from \(updateInfo.currentVersion) to \(updateInfo.newVersion)",
                category: Logger.extensions,
            )
        } catch {
            Logger.error(
                "Failed to apply update for '\(extension_.displayName)': \(error)",
                category: Logger.extensions,
            )
        }

        // Clean up
        try? FileManager.default.removeItem(at: downloadedURL)

        // Remove from pending
        pendingUpdates.removeValue(forKey: extension_.id)
    }

    /// Stores a downloaded update for later application.
    private func storeDownloadedUpdate(
        _: UUID,
        url _: URL,
        info _: UpdateInfo,
    ) async {
        // In a full implementation, this would store the download location
        // for later use when the user confirms the update
    }

    /// Sends a notification about an available update.
    private func sendUpdateNotification(
        _ extension_: InstalledExtension,
        updateInfo: UpdateInfo,
    ) async {
        // Send macOS notification
        let content = UNMutableNotificationContent()
        content.title = "Extension Update Available"
        content.body = "\(extension_.displayName) can be updated to version \(updateInfo.newVersion)"
        content.sound = .default
        content.userInfo = ["extensionID": extension_.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "extension-update-\(extension_.id.uuidString)",
            content: content,
            trigger: nil,
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Extracts version from a CRX download URL.
    private func extractVersionFromCRXURL(_ url: URL) -> String? {
        // Chrome Web Store URLs sometimes contain version info
        // This is a best-effort extraction
        let components = url.pathComponents
        for component in components {
            if component.contains("."), component.first?.isNumber == true {
                return component
            }
        }
        return nil
    }

    /// Compares two version strings.
    private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let v1Parts = v1.split(separator: ".").compactMap { Int($0) }
        let v2Parts = v2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(v1Parts.count, v2Parts.count)

        for i in 0 ..< maxLength {
            let part1 = i < v1Parts.count ? v1Parts[i] : 0
            let part2 = i < v2Parts.count ? v2Parts[i] : 0

            if part1 < part2 { return .orderedAscending }
            if part1 > part2 { return .orderedDescending }
        }

        return .orderedSame
    }
}

// MARK: - Update Errors

/// Errors that can occur during update operations.
enum UpdateError: Error, LocalizedError {
    case noUpdateAvailable
    case updateAlreadyInProgress
    case invalidURL
    case invalidResponse
    case downloadFailed
    case managerNotSet
    case extensionNotInGallery

    var errorDescription: String? {
        switch self {
        case .noUpdateAvailable:
            "No update is available for this extension"
        case .updateAlreadyInProgress:
            "An update is already in progress for this extension"
        case .invalidURL:
            "Invalid update URL"
        case .invalidResponse:
            "Invalid response from update server"
        case .downloadFailed:
            "Failed to download update"
        case .managerNotSet:
            "Extension manager not configured"
        case .extensionNotInGallery:
            "Extension not found in gallery"
        }
    }
}
