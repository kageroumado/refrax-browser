import Foundation
import Security

/// Manages the complete app update lifecycle: checking, downloading, installing,
/// and post-update notification.
///
/// ## Overview
///
/// `AppUpdateManager` implements the Chrome/Arc update model: updates are checked
/// automatically, downloaded in the background, and the user is prompted to restart
/// when the update is ready. No user interaction is needed until restart.
///
/// ## Update Channels
///
/// The active channel is determined at compile time:
/// - **Alpha** (`release` builds): Checks `refrax.website` for updates
/// - **Localhost** (`debug` builds): Checks `localhost:8080`, with force-update
///   enabled (skips version comparison for testing)
///
/// ## State Machine
///
/// ```
/// idle → checking → downloading(progress) → readyToInstall → installing → (quit)
///   ↑        ↓              ↓
///   └── (no update)    (cancelled/failed)
/// ```
///
/// ## Triggers
///
/// Update checks are initiated by:
/// - **Background scheduler**: ``ScheduledTasksManager`` runs hourly via
///   `NSBackgroundActivityScheduler`, deferred by system based on battery/thermal state
/// - **App activation**: After 60+ minutes idle, via ``AppActivationObserver``
/// - **Manual**: Menu bar "Check for Updates…" or Command Lens "Check for Updates"
/// - **Startup**: Immediate check during ``RefraxAppDelegate/startDeferredMaintenance()``
///
/// When an update is found, download begins automatically. No user action required.
///
/// ## Installation Process
///
/// When the user clicks "Restart to Update":
/// 1. Translocation guard — refuse to update a translocated (unmovable) bundle
/// 2. Downloaded DMG mounted via `hdiutil` (no-browse, quiet, checksum verified)
/// 3. `.app` located in mount point (symlinks skipped)
/// 4. New `.app` copied to a unique 0700 staging directory
/// 5. DMG unmounted
/// 6. Staged copy verified: signature validity against the running app's
///    designated requirement, bundle identifier match, downgrade rejection
/// 7. Post-update metadata saved to UserDefaults
/// 8. Updater shell script written to temp and launched
/// 9. App terminates
/// 10. Script waits for process exit → swaps bundle with rollback on failure
///     → removes quarantine → relaunches
///
/// ## Post-Update Detection
///
/// On launch, ``detectPostUpdate()`` checks UserDefaults for `pendingUpdateVersion`:
/// - Sets ``justUpdated`` with version, previous version, and release notes
/// - Sidebar shows ``UpdateNotificationPanel`` (auto-dismisses after 60s)
/// - Tapping the panel opens ``UpdateCompletedSheet`` with full release notes
/// - UserDefaults keys are cleared
///
/// ## User Preferences
///
/// - `BrowserSettings.checkForUpdatesAutomatically`: Enables/disables background checks
@Observable
@MainActor
final class AppUpdateManager {
    // MARK: - Types

    /// Lifecycle state of the update system.
    ///
    /// Transitions:
    /// ```
    /// idle → checking → downloading(progress) → readyToInstall → installing
    ///   ↑        ↓              ↓                                     ↓
    ///   └── (no update)    (cancelled/failed)                    (app quits)
    /// ```
    enum UpdatePhase: Equatable {
        /// No update activity.
        case idle
        /// Querying the releases endpoint.
        case checking
        /// DMG download in progress. `progress` is 0.0–1.0.
        case downloading(progress: Double)
        /// Download complete, waiting for user to restart.
        case readyToInstall(AppUpdate)
        /// Mounting DMG, staging app, launching updater.
        case installing
        /// An error occurred during check or download.
        case failed(String)
    }

    /// Information about a successfully completed update, shown post-relaunch.
    struct PostUpdateInfo: Equatable {
        let version: String
        let previousVersion: String
        let releaseNotes: String
    }

    // MARK: - Observable State

    /// Current phase of the update lifecycle.
    var phase: UpdatePhase = .idle

    /// Set on launch after a successful update. Drives the notification panel.
    var justUpdated: PostUpdateInfo?

    /// When `true`, the sidebar notification panel shows the failure error message.
    /// Set by clicking the warning icon in the sidebar bottom controls.
    var showFailedPanel = false

    /// When `true`, the sidebar shows the crash report notification panel.
    /// Set after an automatic crash report is submitted on relaunch.
    var crashReportSent = false

    /// When the last successful check completed.
    var lastCheckDate: Date?

    // MARK: - Dependencies

    @ObservationIgnored
    unowned let settings: BrowserSettings

    // MARK: - Private State

    @ObservationIgnored
    private var downloadTask: URLSessionDownloadTask?

    @ObservationIgnored
    private var progressObservation: NSKeyValueObservation?

    @ObservationIgnored
    private var downloadedDMGPath: URL?

    @ObservationIgnored
    private var pendingUpdate: AppUpdate?

    // MARK: - UserDefaults Keys

    private enum UDKey {
        static let pendingVersion = "pendingUpdateVersion"
        static let pendingPreviousVersion = "pendingUpdatePreviousVersion"
        static let pendingNotes = "pendingUpdateNotes"
    }

    // MARK: - Initialization

    init(settings: BrowserSettings) {
        self.settings = settings
    }

    // MARK: - Update Check

    /// Checks for available updates and begins download automatically if found.
    ///
    /// - Parameter manual: When `true`, ignores the `checkForUpdatesAutomatically`
    ///   setting. Use for user-initiated checks from the menu bar or Command Lens.
    func checkForUpdates(manual: Bool = false) async {
        if !manual, !settings.checkForUpdatesAutomatically {
            return
        }

        // Skip automatic checks right after a successful update
        if !manual, justUpdated != nil {
            return
        }

        // Don't interrupt an active check, download, or installation
        switch phase {
        case .checking, .downloading, .installing:
            return
        case .readyToInstall, .idle, .failed:
            break
        }

        let pendingVersion: String? = if case .readyToInstall(let pending) = phase {
            pending.version
        } else {
            nil
        }

        phase = .checking

        do {
            let update = try await AppUpdateChecker.check(
                currentVersion: Constants.App.version,
                currentBuild: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleVersion",
                ) as? String ?? "1",
            )

            lastCheckDate = .now

            if let update {
                // If we already have this version downloaded, restore readyToInstall
                if let pendingVersion, update.version == pendingVersion {
                    phase = .readyToInstall(update)
                } else {
                    // Newer version available — discard stale download and fetch new one
                    if pendingVersion != nil {
                        Logger.info(
                            "Superseding pending v\(pendingVersion!) with v\(update.version)",
                            category: Logger.updates,
                        )
                        discardPendingDownload()
                    }
                    Logger.info("Update available: v\(update.version)", category: Logger.updates)
                    startDownload(update)
                }
            } else {
                restoreOrIdle(pendingVersion: pendingVersion)
            }
        } catch is CancellationError {
            restoreOrIdle(pendingVersion: pendingVersion)
        } catch {
            Logger.error("Update check failed: \(error.localizedDescription)", category: Logger.updates)
            // If we had a pending download, don't lose it over a transient check failure
            restoreOrIdle(pendingVersion: pendingVersion)
        }
    }

    // MARK: - Download

    /// Cancels an in-progress download.
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation = nil
        pendingUpdate = nil
        phase = .idle
    }

    /// Restores readyToInstall if we had a pending download, otherwise goes idle.
    private func restoreOrIdle(pendingVersion: String?) {
        if pendingVersion != nil, let pending = pendingUpdate {
            phase = .readyToInstall(pending)
        } else {
            phase = .idle
        }
    }

    /// Removes a previously downloaded DMG that's no longer the latest version.
    private func discardPendingDownload() {
        if let path = downloadedDMGPath {
            try? FileManager.default.removeItem(at: path)
        }
        downloadedDMGPath = nil
        pendingUpdate = nil
    }

    /// Dismisses the failure panel and resets phase to idle.
    ///
    /// Called when the user closes the error notification panel. Update checks
    /// will resume on the next background scheduler cycle.
    func dismissFailure() {
        showFailedPanel = false
        phase = .idle
    }

    // MARK: - Installation

    /// Initiates the update installation process.
    ///
    /// Mounts the downloaded DMG, verifies code signing, stages the new app,
    /// writes the updater script, and terminates the current app.
    ///
    /// Called when the user clicks "Restart Now" in the update UI.
    func restartToUpdate() async {
        guard case .readyToInstall(let update) = phase,
              let dmgPath = downloadedDMGPath
        else { return }

        phase = .installing

        do {
            try await installUpdate(update: update, dmgPath: dmgPath)
        } catch {
            Logger.error("Installation failed: \(error.localizedDescription)", category: Logger.updates)
            phase = .failed(error.localizedDescription)
        }
    }

    private func installUpdate(update: AppUpdate, dmgPath: URL) async throws {
        // 1. Refuse to update a translocated bundle — the swap would
        // half-complete against the read-only translocated path
        guard !Bundle.main.bundlePath.contains("/AppTranslocation/") else {
            throw AppUpdateError.appTranslocated
        }

        // 2. Mount DMG
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try await mountDMG(at: dmgPath, mountPoint: mountPoint)

        // 3. Find .app in mount
        let appURL = try findApp(in: mountPoint)

        // 4. Stage into a unique directory (per-user temp is 0700; the UUID
        // prevents another process from pre-creating the staging path)
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let staged = stagingDirectory.appendingPathComponent(appURL.lastPathComponent)
        try FileManager.default.copyItem(at: appURL, to: staged)

        // 5. Unmount DMG
        try await unmountDMG(mountPoint: mountPoint)

        // 6. Verify the staged copy — the exact bytes that get installed:
        // signature validity against our designated requirement, then
        // bundle identity and downgrade rejection from its Info.plist
        try verifyCodeSigning(candidate: staged, current: Bundle.main.bundleURL)
        try verifyStagedIdentity(staged: staged)

        // 7. Save post-update info to UserDefaults
        UserDefaults.standard.set(update.version, forKey: UDKey.pendingVersion)
        UserDefaults.standard.set(Constants.App.version, forKey: UDKey.pendingPreviousVersion)
        UserDefaults.standard.set(update.releaseNotes, forKey: UDKey.pendingNotes)

        // 8. Write & launch updater script
        let scriptURL = try writeUpdaterScript()
        try launchUpdater(
            script: scriptURL,
            staged: staged,
            installPath: Bundle.main.bundleURL,
        )

        // 9. Quit — use exit(0) to bypass AppKit's applicationShouldTerminate:
        // which can delay or cancel termination. The updater script handles
        // waiting for the process to exit before replacing the bundle.
        Logger.info("Terminating for update installation", category: Logger.updates)
        exit(0)
    }

    // MARK: - Post-Update Detection

    /// Checks for post-update metadata left by a previous installation.
    ///
    /// Called during ``RefraxAppDelegate/startDeferredMaintenance()`` on launch.
    /// If found, sets ``justUpdated`` to drive the notification panel and clears
    /// the UserDefaults keys.
    func detectPostUpdate() {
        guard let version = UserDefaults.standard.string(forKey: UDKey.pendingVersion) else {
            return
        }

        let previousVersion = UserDefaults.standard.string(forKey: UDKey.pendingPreviousVersion) ?? ""
        let notes = UserDefaults.standard.string(forKey: UDKey.pendingNotes) ?? ""

        justUpdated = PostUpdateInfo(
            version: version,
            previousVersion: previousVersion,
            releaseNotes: notes,
        )

        // Clear keys
        UserDefaults.standard.removeObject(forKey: UDKey.pendingVersion)
        UserDefaults.standard.removeObject(forKey: UDKey.pendingPreviousVersion)
        UserDefaults.standard.removeObject(forKey: UDKey.pendingNotes)

        // Remove downloaded update DMGs — the update they carried is installed
        let tmp = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for item in items
                where item.lastPathComponent.hasPrefix("Refrax-update-") && item.pathExtension == "dmg" {
                try? FileManager.default.removeItem(at: item)
            }
        }

        Logger.info("Post-update detected: v\(previousVersion) → v\(version)", category: Logger.updates)
    }

    // MARK: - DMG Operations

    private func mountDMG(at dmgPath: URL, mountPoint: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        // No -noverify: the UDIF checksum is a free integrity check
        // (catches corruption, not tampering)
        process.arguments = [
            "attach", dmgPath.path,
            "-mountpoint", mountPoint.path,
            "-nobrowse", "-quiet", "-noautoopen",
        ]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AppUpdateError.dmgMountFailed(errorMessage)
        }
    }

    private func unmountDMG(mountPoint: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]

        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: mountPoint)
    }

    private func findApp(in mountPoint: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
        )

        // Skip symlinks — DMGs ship an /Applications symlink, and a crafted
        // image could point an .app-named link outside the mount
        let app = contents.first { url in
            url.pathExtension == "app"
                && (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }

        guard let app else {
            throw AppUpdateError.noAppInDMG
        }

        return app
    }

    // MARK: - Code Signing Verification

    /// Verifies the candidate's signature validity against the running app's
    /// designated requirement.
    ///
    /// `SecStaticCodeCheckValidityWithErrors` validates the whole signature —
    /// identity, team ID, and integrity of the signed bytes — so a resigned or
    /// tampered bundle fails even when its bundle identifier matches.
    ///
    /// If the running app is unsigned (common during development), verification
    /// is skipped with a warning.
    private func verifyCodeSigning(candidate: URL, current: URL) throws {
        var currentCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(current as CFURL, [], &currentCode) == errSecSuccess,
              let currentCode
        else {
            throw AppUpdateError.codeSigningFailed
        }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
              let requirement
        else {
            // Unsigned running app has no designated requirement — dev builds only
            Logger.warning(
                "Running app has no designated requirement — skipping code signing verification",
                category: Logger.updates,
            )
            return
        }

        var candidateCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &candidateCode) == errSecSuccess,
              let candidateCode
        else {
            throw AppUpdateError.codeSigningFailed
        }

        var validationError: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(
            candidateCode,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
            requirement,
            &validationError,
        )

        guard status == errSecSuccess else {
            let detail = validationError.map { String(describing: $0.takeRetainedValue()) }
                ?? "OSStatus \(status)"
            Logger.error(
                "Update failed code signing validation: \(detail)",
                category: Logger.updates,
            )
            throw AppUpdateError.codeSigningMismatch
        }

        Logger.info(
            "Code signing verified against designated requirement",
            category: Logger.updates,
        )
    }

    // MARK: - Staged App Identity

    /// Verifies the staged app's bundle identity and rejects downgrades.
    ///
    /// Reads the staged copy's `Info.plist` directly:
    /// - `CFBundleIdentifier` must match the running app, so a DMG that ships
    ///   some other (validly signed) app can't be installed over Refrax.
    /// - `CFBundleVersion` must be strictly greater than the running build,
    ///   so a replayed old release can't roll users back. The force-update
    ///   debug channel is exempt to keep localhost testing working.
    private func verifyStagedIdentity(staged: URL) throws {
        let infoURL = staged.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String,
              let stagedBuild = info["CFBundleVersion"] as? String
        else {
            throw AppUpdateError.stagedAppUnreadable
        }

        guard bundleID == Bundle.main.bundleIdentifier else {
            Logger.error(
                "Staged app bundle identifier mismatch: \(bundleID)",
                category: Logger.updates,
            )
            throw AppUpdateError.bundleIdentityMismatch
        }

        if !Constants.API.channel.forceUpdate {
            let currentBuild = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion",
            ) as? String ?? "0"
            guard (Int(stagedBuild) ?? 0) > (Int(currentBuild) ?? 0) else {
                Logger.error(
                    "Staged app is not newer: build \(stagedBuild) vs running \(currentBuild)",
                    category: Logger.updates,
                )
                throw AppUpdateError.downgrade
            }
        }
    }

    // MARK: - Updater Script

    private func writeUpdaterScript() throws -> URL {
        let script = """
        #!/bin/bash
        # Refrax Updater — replaces app bundle and relaunches
        PID="$1"; STAGED="$2"; INSTALL="$3"
        OLD="${INSTALL}.old"

        # Wait for app to quit (max 30s)
        for _ in $(seq 1 60); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.5
        done

        # Ordered swap with rollback — never leave zero apps installed
        rm -rf "$OLD"
        mv "$INSTALL" "$OLD" || exit 1
        if ! mv "$STAGED" "$INSTALL"; then
            mv "$OLD" "$INSTALL"
            open "$INSTALL"
            exit 1
        fi
        xattr -dr com.apple.quarantine "$INSTALL"
        rmdir "$(dirname "$STAGED")" 2>/dev/null

        # Relaunch
        open "$INSTALL"

        # Deferred cleanup (give open time to start the app)
        sleep 2
        rm -rf "$OLD"
        rm -- "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-updater-\(UUID().uuidString).sh")

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path,
        )

        return scriptURL
    }

    private func launchUpdater(script: URL, staged: URL, installPath: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            script.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            staged.path,
            installPath.path,
        ]

        try process.run()
    }
}

// MARK: - Download with Completion Handler

extension AppUpdateManager {
    /// Starts a download using URLSession's completion handler API to properly
    /// receive the temporary file URL.
    private func startDownload(_ update: AppUpdate) {
        pendingUpdate = update
        phase = .downloading(progress: 0)

        let request = URLRequest(url: update.downloadURL)
        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                self?.handleDownloadResult(tempURL: tempURL, error: error, update: update)
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.phase = .downloading(progress: progress.fractionCompleted)
            }
        }

        task.resume()
        downloadTask = task

        Logger.info("Started downloading update v\(update.version)", category: Logger.updates)
    }

    private func handleDownloadResult(tempURL: URL?, error: (any Error)?, update: AppUpdate) {
        progressObservation = nil

        if let error {
            Logger.error("Download failed: \(error.localizedDescription)", category: Logger.updates)
            phase = .failed(error.localizedDescription)
            return
        }

        guard let tempURL else {
            phase = .failed("Download completed but no file was received")
            return
        }

        // Move to a stable temp location before the system cleans up
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Refrax-update-\(update.version).dmg")

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            downloadedDMGPath = destination
            phase = .readyToInstall(update)
            Logger.info("Download complete: v\(update.version)", category: Logger.updates)
        } catch {
            Logger.error("Failed to move downloaded DMG: \(error.localizedDescription)", category: Logger.updates)
            phase = .failed("Failed to save downloaded update")
        }
    }
}

// MARK: - Errors

/// Errors that can occur during the update installation process.
nonisolated enum AppUpdateError: Error, LocalizedError {
    case dmgMountFailed(String)
    case noAppInDMG
    case codeSigningMismatch
    case codeSigningFailed
    case stagedAppUnreadable
    case bundleIdentityMismatch
    case downgrade
    case appTranslocated

    var errorDescription: String? {
        switch self {
        case let .dmgMountFailed(reason):
            "Failed to mount update DMG: \(reason)"
        case .noAppInDMG:
            "No application found in update DMG"
        case .codeSigningMismatch:
            "Update failed code signature validation"
        case .codeSigningFailed:
            "Failed to verify update code signing"
        case .stagedAppUnreadable:
            "Couldn't read the update's application bundle"
        case .bundleIdentityMismatch:
            "Update is not Refrax (bundle identifier mismatch)"
        case .downgrade:
            "Update is older than the installed version"
        case .appTranslocated:
            "Move Refrax to the Applications folder before updating"
        }
    }
}
