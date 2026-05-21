import Foundation
import Observation
import WebKit

/// Key for tracking extension contexts in isolated/private spaces.
private struct SpaceExtensionKey: Hashable {
    let spaceID: UUID
    let extensionIdentifier: String
}

/// Tracks whether a space controller is persistent or transient.
private enum ControllerType {
    /// Persistent controller with storage linked to space ID.
    case persistent
    /// Transient controller for private spaces (no persistence).
    case transient
}

/// Manages browser extension lifecycle and integration.
///
/// `ExtensionManager` is the primary coordinator for all extension operations.
/// It manages `WKWebExtensionController` instances and bridges between WebKit's
/// extension system and Refrax's architecture.
///
/// ## Multi-Controller Architecture
///
/// To support data isolation per space, ExtensionManager maintains multiple controllers:
///
/// ```
/// ExtensionManager
///     │
///     ├─ defaultController (for normal spaces)
///     │     └─ WKWebExtensionContext[] (shared extensions)
///     │
///     ├─ isolatedControllers[spaceID] (for spaces with usesSeparateDataStore)
///     │     └─ WKWebExtensionContext[] (per-space extension instances, persistent)
///     │
///     ├─ privateControllers[spaceID] (for private spaces)
///     │     └─ WKWebExtensionContext[] (per-space instances, transient/non-persistent)
///     │
///     ├─ InstalledExtension[] (persisted metadata)
///     │
///     └─ Adapters
///           ├─ RefraxExtensionTab (bridges Tab/TabPage)
///           └─ RefraxExtensionWindow (bridges WindowState)
/// ```
///
/// ## Space Isolation Types
///
/// | `dataStoreMode` | Controller | Data Store | Extension Storage |
/// |-----------------|------------|------------|-------------------|
/// | `.global` | `defaultController` | `.default()` | Shared persistent |
/// | `.separate` | `isolatedControllers[id]` | `WKWebsiteDataStore(forIdentifier:)` | Isolated persistent |
/// | `.private` | `privateControllers[id]` | `.nonPersistent()` | None (memory only) |
///
/// Private spaces (`.private` mode) only load extensions with `allowedInPrivateMode = true`.
///
/// ## Integration Points
///
/// 1. **Configuration**: Sets `webExtensionController` on `WebPage.Configuration`
/// 2. **Tab Events**: TabManager calls `dispatchTab*` methods for lifecycle events
/// 3. **Script Registry**: Extension content scripts are registered with `ScriptRegistry`
///
/// ## Initialization
///
/// ExtensionManager is created by AppDelegate and injected into the environment.
/// It requires BrowserState for configuration access and ScriptRegistry for
/// content script management.
///
/// ```swift
/// let extensionManager = ExtensionManager(state: browserState)
/// browserState.webPageConfiguration.webExtensionController = extensionManager.controller
/// ```
@Observable
final class ExtensionManager {
    // MARK: - Properties

    /// The default WebKit extension controller for normal spaces.
    ///
    /// This controller is used for all tabs in spaces that don't have `usesSeparateDataStore = true`.
    let defaultController: WKWebExtensionController

    /// Extension controllers for isolated spaces, keyed by space ID.
    ///
    /// Spaces with `usesSeparateDataStore = true` get their own controller with:
    /// - Unique persistent storage via `WKWebExtensionController.Configuration(identifier:)`
    /// - Linked data store from `SpaceDataStoreManager`
    private var isolatedControllers: [UUID: WKWebExtensionController] = [:]

    /// Extension controllers for private spaces, keyed by space ID.
    ///
    /// Private spaces (`isPrivate = true`) get transient controllers with:
    /// - No persistent storage (default configuration without identifier)
    /// - Non-persistent data store from `SpaceDataStoreManager`
    /// - Only extensions with `allowedInPrivateMode = true` are loaded
    private var privateControllers: [UUID: WKWebExtensionController] = [:]

    /// All installed extensions (persisted metadata).
    private(set) var installedExtensions: [InstalledExtension] = []

    /// Global extension settings.
    private(set) var globalSettings = ExtensionGlobalSettings()

    /// Currently loaded extension contexts in the default controller, keyed by unique identifier.
    private var loadedContexts: [String: WKWebExtensionContext] = [:]

    /// Extension contexts loaded into isolated controllers, keyed by (spaceID, extensionIdentifier).
    private var isolatedContexts: [SpaceExtensionKey: WKWebExtensionContext] = [:]

    /// Extension tab adapters, keyed by TabPage ID.
    private var tabAdapters: [TabPage.ID: RefraxExtensionTab] = [:]

    /// Extension window adapters, keyed by WindowState object identity.
    private var windowAdapters: [ObjectIdentifier: RefraxExtensionWindow] = [:]

    // MARK: - Dependencies

    /// Browser state for accessing tab/window managers.
    unowned let state: BrowserState

    /// Manager for handling permission prompts.
    let permissionPromptManager = PermissionPromptManager()

    /// Manager for handling extension popup presentation.
    let popupManager = ExtensionPopupManager()

    /// Security analyzer for evaluating extension risks.
    let securityAnalyzer = ExtensionSecurityAnalyzer()

    /// Gallery service for browsing curated extensions.
    let galleryService = ExtensionGalleryService()

    /// Resource monitor for tracking extension memory, CPU, and network usage.
    let resourceMonitor = ExtensionResourceMonitor()

    /// Recovery manager for handling extension crashes and auto-restart.
    let recoveryManager = ExtensionRecoveryManager()

    /// Update checker for monitoring and applying extension updates.
    let updateChecker = ExtensionUpdateChecker()

    /// Shim injector for API compatibility.
    private(set) var shimInjector: ShimInjector!

    /// The controller delegate handling extension callbacks (for default controller).
    private var controllerDelegate: ExtensionControllerDelegate?

    /// Delegates for isolated controllers, keyed by space ID.
    private var isolatedDelegates: [UUID: ExtensionControllerDelegate] = [:]

    /// Delegates for private controllers, keyed by space ID.
    private var privateDelegates: [UUID: ExtensionControllerDelegate] = [:]

    /// Extension contexts loaded into private controllers, keyed by (spaceID, extensionIdentifier).
    private var privateContexts: [SpaceExtensionKey: WKWebExtensionContext] = [:]

    /// Data store manager for per-space data stores.
    ///
    /// Set after initialization to link extension controllers to their space's data store.
    unowned var dataStoreManager: SpaceDataStoreManager!

    /// App activation observer for pausing resource monitoring when app is inactive.
    ///
    /// Set after initialization. When set, starts observing app activation state
    /// to pause/resume extension resource monitoring.
    var activationObserver: AppActivationObserver? {
        didSet {
            if let observer = activationObserver {
                startAppActivationObservation(observer)
            }
        }
    }

    /// Task for observing app activation state changes.
    private var activationObservationTask: Task<Void, Never>?

    isolated deinit {
        activationObservationTask?.cancel()
    }

    // MARK: - Persistence

    /// Path to extension state file.
    private var stateFileURL: URL {
        let extensionsDir = Directories.appStorage.appendingPathComponent("Extensions", isDirectory: true)
        return extensionsDir.appendingPathComponent("state.json")
    }

    // MARK: - Initialization

    /// Creates an extension manager.
    ///
    /// - Parameter state: The browser state for configuration access.
    init(state: BrowserState) {
        self.state = state

        // Create the default extension controller
        let configuration = WKWebExtensionController.Configuration.default()
        self.defaultController = WKWebExtensionController(configuration: configuration)

        // Set up delegate
        let delegate = ExtensionControllerDelegate(manager: self)
        self.controllerDelegate = delegate
        defaultController.delegate = delegate

        // Create shim injector (must be after self is fully initialized)
        self.shimInjector = ShimInjector(extensionManager: self)

        // Wire up recovery manager
        recoveryManager.extensionManager = self

        // Wire up update checker
        Task {
            await updateChecker.setExtensionManager(self)
        }

        // Load persisted extension state
        loadPersistedState()
    }

    // MARK: - Setup

    /// Completes async setup after initialization.
    ///
    /// Call this after dependencies are wired up. It:
    /// 1. Installs bundled extensions on first launch
    /// 2. Loads and enables persisted extensions
    /// 3. Starts resource monitoring for each extension
    /// 4. Registers extension scripts with ScriptRegistry
    func setup() async {
        // Install bundled extensions on first launch
        await installBundledExtensionsIfNeeded()

        // Load each installed extension that was enabled
        for installedExtension in installedExtensions where installedExtension.isEnabled {
            do {
                try await loadExtension(installedExtension)

                // Start resource monitoring
                await resourceMonitor.startMonitoring(for: installedExtension)
            } catch {
                Logger.error(
                    "Failed to load extension '\(installedExtension.displayName)': \(error)",
                    category: Logger.extensions,
                )

                // Record the error for recovery tracking
                recoveryManager.recordError(error, for: installedExtension)
            }
        }
    }

    // MARK: - Bundled Extensions

    /// Bundled extensions shipped with Refrax.
    ///
    /// Each entry is (bundleName, resourceFileName).
    /// These are auto-installed on first launch.
    private static let bundledExtensions: [(name: String, fileName: String)] = [
        ("ublock-origin", "ublock_origin-1.68.0.xpi"),
    ]

    /// Installs bundled extensions that haven't been installed yet.
    ///
    /// This is called during `setup()` to auto-install extensions shipped
    /// with the app bundle. Extensions are only installed once - the installed
    /// set is tracked in global settings.
    private func installBundledExtensionsIfNeeded() async {
        for (name, fileName) in Self.bundledExtensions {
            // Skip if already installed
            guard !globalSettings.installedBundledExtensions.contains(name) else {
                Logger.debug("Bundled extension '\(name)' already installed, skipping", category: Logger.extensions)
                continue
            }

            // Find the XPI in the app bundle
            // First try BundledExtensions subdirectory, then fall back to main Resources
            let bundleURL: URL? = Bundle.main.url(
                forResource: fileName.replacingOccurrences(of: ".xpi", with: ""),
                withExtension: "xpi",
                subdirectory: "BundledExtensions",
            ) ?? Bundle.main.url(
                forResource: fileName.replacingOccurrences(of: ".xpi", with: ""),
                withExtension: "xpi",
            )

            guard let bundleURL else {
                Logger.warning("Bundled extension '\(name)' not found in bundle: \(fileName)", category: Logger.extensions)
                continue
            }

            do {
                let installedExtension = try await installBundledExtension(
                    from: bundleURL,
                    name: name,
                )

                Logger.info(
                    "Installed bundled extension '\(installedExtension.displayName)' v\(installedExtension.version)",
                    category: Logger.extensions,
                )
            } catch {
                Logger.error("Failed to install bundled extension '\(name)': \(error)", category: Logger.extensions)
            }
        }
    }

    /// Installs a bundled extension from the app bundle.
    ///
    /// - Parameters:
    ///   - url: URL to the XPI in the app bundle.
    ///   - name: The bundled extension name for tracking.
    /// - Returns: The installed extension metadata.
    @discardableResult
    private func installBundledExtension(from url: URL, name: String) async throws -> InstalledExtension {
        // Extract to extensions directory (runs on background thread)
        let extractedURL = try await extractArchive(url)

        // Create the WKWebExtension from the extracted folder
        let extension_ = try await WKWebExtension(resourceBaseURL: extractedURL)

        // Validate the extension
        if !extension_.errors.isEmpty {
            // Clean up extracted folder on failure
            try? FileManager.default.removeItem(at: extractedURL)
            throw ExtensionError.manifestErrors(extension_.errors.map(\.localizedDescription))
        }

        // Create persisted metadata with bundled source
        var installedExtension = InstalledExtension(
            uniqueIdentifier: extractedURL.lastPathComponent,
            source: .bundled(name: name),
            displayName: extension_.displayName ?? name,
            version: extension_.displayVersion ?? "0.0.0",
            manifestVersion: extension_.manifest["manifest_version"] as? Double ?? 3,
        )
        installedExtension.description = extension_.displayDescription

        // Create the context
        let context = WKWebExtensionContext(for: extension_)
        installedExtension = updateFromContext(installedExtension, context: context)

        // Auto-grant all requested permissions for bundled extensions
        grantAllPermissions(for: context, extension_: extension_, installedExtension: &installedExtension)

        // Cache the icon if available
        if let icon = extension_.icon(for: CGSize(width: 128, height: 128)) {
            installedExtension.iconData = icon.tiffRepresentation
        }

        // Enable Web Inspector for debug builds
        configureInspection(for: context)

        // Load the extension into the default controller
        try defaultController.load(context)
        loadedContexts[installedExtension.uniqueIdentifier] = context

        // Configure shims after loading (webViewConfiguration is only available after load)
        shimInjector.configure(context: context)

        // Persist the extension
        installedExtensions.append(installedExtension)

        // Mark bundled extension as installed
        globalSettings.installedBundledExtensions.insert(name)
        savePersistedState()

        // Start resource monitoring
        await resourceMonitor.startMonitoring(for: installedExtension)

        return installedExtension
    }

    // MARK: - Controller Access

    /// Returns the appropriate extension controller for a space.
    ///
    /// - For private spaces (`isPrivate = true`): returns a transient controller
    ///   with non-persistent storage and only private-mode-allowed extensions.
    /// - For spaces with `usesSeparateDataStore = true`: returns a dedicated controller
    ///   that uses the space's isolated persistent data store.
    /// - For normal spaces: returns the shared `defaultController`.
    ///
    /// - Parameter space: The space to get a controller for.
    /// - Returns: The extension controller to use for tabs in this space.
    func controller(for space: Space) -> WKWebExtensionController {
        // Private spaces get transient controllers
        if space.dataStoreMode.isPrivate {
            if let existing = privateControllers[space.id] {
                return existing
            }
            return createPrivateController(for: space)
        }

        // Separate data store spaces get persistent isolated controllers
        if space.dataStoreMode.usesSeparateDataStore {
            if let existing = isolatedControllers[space.id] {
                return existing
            }
            return createIsolatedController(for: space)
        }

        // Normal spaces use the shared default controller
        return defaultController
    }

    /// Creates a new isolated extension controller for a space.
    ///
    /// The controller is configured with:
    /// - Unique persistent storage using the space's UUID
    /// - The space's isolated data store from `SpaceDataStoreManager`
    ///
    /// - Parameter space: The space to create a controller for.
    /// - Returns: A new isolated extension controller.
    private func createIsolatedController(for space: Space) -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(identifier: space.id)

        // Link the controller to the space's data store
        if let dataStoreManager {
            configuration.defaultWebsiteDataStore = dataStoreManager.dataStore(for: space)
        }

        let controller = WKWebExtensionController(configuration: configuration)

        // Set up delegate
        let delegate = ExtensionControllerDelegate(manager: self)
        isolatedDelegates[space.id] = delegate
        controller.delegate = delegate

        isolatedControllers[space.id] = controller

        Logger.info("Created isolated extension controller for space: \(space.name)", category: Logger.extensions)

        return controller
    }

    /// Creates a new transient extension controller for a private space.
    ///
    /// The controller is configured with:
    /// - No persistent storage (uses default configuration without identifier)
    /// - Non-persistent data store from `SpaceDataStoreManager`
    ///
    /// Only extensions with `allowedInPrivateMode = true` will be loaded into this controller.
    ///
    /// - Parameter space: The private space to create a controller for.
    /// - Returns: A new transient extension controller.
    private func createPrivateController(for space: Space) -> WKWebExtensionController {
        // Use default configuration (no identifier) for transient storage
        let configuration = WKWebExtensionController.Configuration.default()

        // Link to the space's non-persistent data store
        if let dataStoreManager {
            configuration.defaultWebsiteDataStore = dataStoreManager.dataStore(for: space)
        }

        let controller = WKWebExtensionController(configuration: configuration)

        // Set up delegate
        let delegate = ExtensionControllerDelegate(manager: self)
        privateDelegates[space.id] = delegate
        controller.delegate = delegate

        privateControllers[space.id] = controller

        Logger.info("Created transient extension controller for private space: \(space.name)", category: Logger.extensions)

        return controller
    }

    /// Ensures extensions are loaded for a space.
    ///
    /// For isolated/private spaces, this loads enabled extensions into the space's controller.
    /// Call this when a space is first accessed or when extensions are installed.
    ///
    /// - For private spaces: only loads extensions with `allowedInPrivateMode = true`
    /// - For isolated spaces: loads all enabled extensions
    ///
    /// - Parameter space: The space to load extensions for.
    func ensureExtensionsLoaded(for space: Space) async {
        // Only isolated and private spaces need per-space extension loading
        guard space.dataStoreMode.usesSeparateDataStore || space.dataStoreMode.isPrivate else { return }

        let controller = controller(for: space)
        let isPrivateSpace = space.dataStoreMode.isPrivate
        let contextStore = isPrivateSpace ? privateContexts : isolatedContexts

        for installedExtension in installedExtensions where installedExtension.isEnabled {
            // Private spaces only allow extensions explicitly marked for private mode
            if isPrivateSpace, !installedExtension.allowedInPrivateMode {
                continue
            }

            let key = SpaceExtensionKey(spaceID: space.id, extensionIdentifier: installedExtension.uniqueIdentifier)

            // Skip if already loaded
            guard contextStore[key] == nil else { continue }

            do {
                try await loadExtension(
                    installedExtension,
                    into: controller,
                    spaceID: space.id,
                    isPrivate: isPrivateSpace,
                )
            } catch {
                Logger.error(
                    "Failed to load extension '\(installedExtension.displayName)' for space \(space.name): \(error)",
                    category: Logger.extensions,
                )
            }
        }
    }

    /// Removes the controller and its resources for a space.
    ///
    /// Call this when a space with `usesSeparateDataStore` or `isPrivate` is deleted/closed.
    ///
    /// - Parameter space: The space whose controller should be removed.
    func removeController(for space: Space) {
        // Handle private space cleanup
        if space.dataStoreMode.isPrivate {
            guard privateControllers[space.id] != nil else { return }

            // Remove all contexts for this private space
            let keysToRemove = privateContexts.keys.filter { $0.spaceID == space.id }
            for key in keysToRemove {
                privateContexts.removeValue(forKey: key)
            }

            // Remove controller and delegate
            privateControllers.removeValue(forKey: space.id)
            privateDelegates.removeValue(forKey: space.id)

            Logger.info("Removed transient extension controller for private space: \(space.name)", category: Logger.extensions)
            return
        }

        // Handle isolated (persistent) space cleanup
        guard isolatedControllers[space.id] != nil else { return }

        // Remove all contexts for this space
        let keysToRemove = isolatedContexts.keys.filter { $0.spaceID == space.id }
        for key in keysToRemove {
            isolatedContexts.removeValue(forKey: key)
        }

        // Remove controller and delegate
        isolatedControllers.removeValue(forKey: space.id)
        isolatedDelegates.removeValue(forKey: space.id)

        Logger.info("Removed isolated extension controller for space: \(space.name)", category: Logger.extensions)
    }

    // MARK: - Installation

    /// Installs an extension from a local folder.
    ///
    /// This is the primary installation method for development. The folder must
    /// contain a valid manifest.json.
    ///
    /// - Parameter url: Path to the extension folder.
    /// - Returns: The installed extension metadata.
    /// - Throws: If the extension cannot be loaded or has an invalid manifest.
    @discardableResult
    func installFromFolder(_ url: URL) async throws -> InstalledExtension {
        // Create the WKWebExtension from the folder
        let extension_ = try await WKWebExtension(resourceBaseURL: url)

        // Validate the extension
        if !extension_.errors.isEmpty {
            throw ExtensionError.manifestErrors(extension_.errors.map(\.localizedDescription))
        }

        // Create persisted metadata
        var installedExtension = InstalledExtension(
            uniqueIdentifier: url.lastPathComponent, // Will be updated from context
            source: .localFolder(url),
            displayName: extension_.displayName ?? url.lastPathComponent,
            version: extension_.displayVersion ?? "0.0.0",
            manifestVersion: extension_.manifest["manifest_version"] as? Double ?? 3,
        )
        installedExtension.description = extension_.displayDescription

        // Create the context
        let context = WKWebExtensionContext(for: extension_)
        installedExtension = updateFromContext(installedExtension, context: context)

        // Configure shims for API compatibility
        shimInjector.configure(context: context)

        // Enable Web Inspector for debug builds
        configureInspection(for: context)

        // Load the extension into the default controller
        try defaultController.load(context)
        loadedContexts[installedExtension.uniqueIdentifier] = context

        // Persist
        installedExtensions.append(installedExtension)
        savePersistedState()

        // Start resource monitoring
        await resourceMonitor.startMonitoring(for: installedExtension)

        Logger.info(
            "Installed extension '\(installedExtension.displayName)' from \(url.path)",
            category: Logger.extensions,
        )

        return installedExtension
    }

    /// Installs an extension from a CRX (Chrome) or XPI (Firefox) archive.
    ///
    /// The archive is extracted to the extensions directory and loaded.
    ///
    /// - Parameter url: Path to the .crx or .xpi file.
    /// - Returns: The installed extension metadata.
    /// - Throws: If the archive cannot be extracted or the extension is invalid.
    @discardableResult
    func installFromArchive(_ url: URL) async throws -> InstalledExtension {
        let fileExtension = url.pathExtension.lowercased()

        guard fileExtension == "crx" || fileExtension == "xpi" else {
            throw ExtensionError.invalidArchiveFormat
        }

        // Extract to extensions directory (runs on background thread)
        let extractedURL = try await extractArchive(url)

        // Determine source type
        let source: ExtensionSource = fileExtension == "crx"
            ? .crxFile(url)
            : .xpiFile(url)

        // Create the WKWebExtension from the extracted folder
        let extension_ = try await WKWebExtension(resourceBaseURL: extractedURL)

        // Validate the extension
        if !extension_.errors.isEmpty {
            // Clean up extracted folder on failure
            try? FileManager.default.removeItem(at: extractedURL)
            throw ExtensionError.manifestErrors(extension_.errors.map(\.localizedDescription))
        }

        // Create persisted metadata
        var installedExtension = InstalledExtension(
            uniqueIdentifier: extractedURL.lastPathComponent,
            source: source,
            displayName: extension_.displayName ?? url.deletingPathExtension().lastPathComponent,
            version: extension_.displayVersion ?? "0.0.0",
            manifestVersion: extension_.manifest["manifest_version"] as? Double ?? 3,
        )
        installedExtension.description = extension_.displayDescription

        // Create the context
        let context = WKWebExtensionContext(for: extension_)
        installedExtension = updateFromContext(installedExtension, context: context)

        // Cache the icon if available
        if let icon = extension_.icon(for: CGSize(width: 128, height: 128)) {
            installedExtension.iconData = icon.tiffRepresentation
        }

        // Enable Web Inspector for debug builds
        configureInspection(for: context)

        // Load the extension into the default controller
        try defaultController.load(context)
        loadedContexts[installedExtension.uniqueIdentifier] = context

        // Configure shims after loading (webViewConfiguration is only available after load)
        shimInjector.configure(context: context)

        // Persist
        installedExtensions.append(installedExtension)
        savePersistedState()

        // Start resource monitoring
        await resourceMonitor.startMonitoring(for: installedExtension)

        Logger.info(
            "Installed extension '\(installedExtension.displayName)' from archive \(url.lastPathComponent)",
            category: Logger.extensions,
        )

        return installedExtension
    }

    /// Installs an extension from Chrome Web Store or Firefox Add-ons.
    ///
    /// Downloads the extension archive, extracts it, and loads it with the
    /// correct `ExtensionSource` so that ``ExtensionUpdateChecker`` can check
    /// for future updates from the same store.
    ///
    /// - Parameters:
    ///   - extensionID: The Chrome extension ID (32-char hash) or Firefox addon slug.
    ///   - store: Which store to download from.
    /// - Returns: The installed extension metadata.
    /// - Throws: If the download or installation fails.
    @discardableResult
    func installFromWebStore(extensionID: String, store: WebStore) async throws -> InstalledExtension {
        // Check for duplicates
        let existingSource: ExtensionSource = switch store {
        case .chrome: .chromeWebStore(extensionID: extensionID)
        case .firefox: .firefoxAddons(extensionID: extensionID)
        }

        if installedExtensions.contains(where: { $0.source == existingSource }) {
            throw ExtensionError.alreadyInstalled
        }

        // Build download URL
        let downloadURLString: String = switch store {
        case .chrome:
            "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=120.0&acceptformat=crx2,crx3&x=id%3D\(extensionID)%26uc"
        case .firefox:
            "https://addons.mozilla.org/firefox/downloads/latest/\(extensionID)/"
        }
        guard let downloadURL = URL(string: downloadURLString) else {
            throw ExtensionError.downloadFailed("Malformed download URL for extension '\(extensionID)'")
        }

        Logger.info(
            "Downloading extension '\(extensionID)' from \(store)",
            category: Logger.extensions,
        )

        // Download to temp file
        let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)

        // Determine file extension from response or store type
        let fileExtension: String
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            fileExtension = contentType.contains("xpi") ? "xpi" : "crx"
        } else {
            fileExtension = store == .chrome ? "crx" : "xpi"
        }

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("webstore-\(extensionID)")
            .appendingPathExtension(fileExtension)
        try? FileManager.default.removeItem(at: archiveURL)
        try FileManager.default.moveItem(at: tempURL, to: archiveURL)

        defer { try? FileManager.default.removeItem(at: archiveURL) }

        // Extract the archive
        let extractedURL = try await extractArchive(archiveURL)

        // Create the WKWebExtension from the extracted folder
        let extension_ = try await WKWebExtension(resourceBaseURL: extractedURL)

        // Validate
        if !extension_.errors.isEmpty {
            try? FileManager.default.removeItem(at: extractedURL)
            throw ExtensionError.manifestErrors(extension_.errors.map(\.localizedDescription))
        }

        // Create persisted metadata with the correct web store source
        var installedExtension = InstalledExtension(
            uniqueIdentifier: extractedURL.lastPathComponent,
            source: existingSource,
            displayName: extension_.displayName ?? extensionID,
            version: extension_.displayVersion ?? "0.0.0",
            manifestVersion: extension_.manifest["manifest_version"] as? Double ?? 3,
        )
        installedExtension.description = extension_.displayDescription

        // Create the context
        let context = WKWebExtensionContext(for: extension_)
        installedExtension = updateFromContext(installedExtension, context: context)

        // Cache icon
        if let icon = extension_.icon(for: CGSize(width: 128, height: 128)) {
            installedExtension.iconData = icon.tiffRepresentation
        }

        // Enable Web Inspector for debug builds
        configureInspection(for: context)

        // Load into default controller
        try defaultController.load(context)
        loadedContexts[installedExtension.uniqueIdentifier] = context

        // Configure shims
        shimInjector.configure(context: context)

        // Persist
        installedExtensions.append(installedExtension)
        savePersistedState()

        // Start resource monitoring
        await resourceMonitor.startMonitoring(for: installedExtension)

        Logger.info(
            "Installed extension '\(installedExtension.displayName)' from \(store) (\(extensionID))",
            category: Logger.extensions,
        )

        return installedExtension
    }

    /// Extracts a CRX or XPI archive to the extensions directory.
    ///
    /// - Parameter archiveURL: Path to the archive file.
    /// - Returns: Path to the extracted extension folder.
    ///
    /// - Note: All blocking I/O is performed on a background thread to avoid
    ///   main-thread stalls during extension installation.
    private func extractArchive(_ archiveURL: URL) async throws -> URL {
        // Capture values needed for background work
        let stateURL = stateFileURL

        // Perform all blocking I/O on background thread
        return try await Task.detached(priority: .userInitiated) {
            let fileExtension = archiveURL.pathExtension.lowercased()
            let data = try Data(contentsOf: archiveURL)

            // CRX files have a header before the ZIP data
            let zipData: Data = if fileExtension == "crx" {
                try Self.extractZipFromCRX(data)
            } else {
                // XPI files are just ZIP files
                data
            }

            // Generate unique folder name
            let extensionID = UUID().uuidString
            let extensionsDir = stateURL.deletingLastPathComponent().appendingPathComponent("Extracted", isDirectory: true)
            let extractDir = extensionsDir.appendingPathComponent(extensionID, isDirectory: true)

            // Create directories
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            // Extract ZIP using Process (unzip command)
            let tempZipPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(extensionID).zip")
            try zipData.write(to: tempZipPath)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", "-o", tempZipPath.path, "-d", extractDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            // Use async continuation instead of blocking waitUntilExit()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempZipPath)

            if process.terminationStatus != 0 {
                try? FileManager.default.removeItem(at: extractDir)
                throw ExtensionError.extractionFailed
            }

            Logger.debug(
                "Extracted archive to: \(extractDir.path)",
                category: Logger.extensions,
            )

            // Apply manifest fixups for WebKit compatibility
            Self.fixupManifest(at: extractDir)

            return extractDir
        }.value
    }

    /// Applies fixes to the manifest.json for WebKit compatibility.
    ///
    /// WebKit's WKWebExtension is stricter than Firefox/Chrome about certain
    /// manifest entries. This method patches known issues:
    ///
    /// - Empty command objects (e.g., `"_execute_browser_action": {}`)
    /// - Other Firefox-specific entries that WebKit rejects
    ///
    /// - Parameter extensionDir: The extracted extension directory.
    private nonisolated static func fixupManifest(at extensionDir: URL) {
        let manifestURL = extensionDir.appendingPathComponent("manifest.json")

        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Logger.warning("Could not read manifest for fixup at: \(manifestURL.path)", category: Logger.extensions)
            return
        }

        var modified = false

        // Fix 1: Remove empty command entries
        // WebKit rejects commands like `"_execute_browser_action": {}`
        if var commands = manifest["commands"] as? [String: Any] {
            let originalCount = commands.count
            commands = commands.filter { _, value in
                guard let commandObj = value as? [String: Any] else { return false }
                // Keep commands that have at least one property (description, suggested_key, etc.)
                return !commandObj.isEmpty
            }

            if commands.count != originalCount {
                manifest["commands"] = commands
                modified = true
                Logger.debug(
                    "Removed \(originalCount - commands.count) empty command(s) from manifest",
                    category: Logger.extensions,
                )
            }
        }

        // Fix 2: Remove browser_specific_settings if present (Firefox-only)
        if manifest["browser_specific_settings"] != nil {
            manifest.removeValue(forKey: "browser_specific_settings")
            modified = true
            Logger.debug("Removed browser_specific_settings from manifest", category: Logger.extensions)
        }

        // Write back if modified
        if modified {
            do {
                let fixedData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                try fixedData.write(to: manifestURL, options: .atomic)
                Logger.info("Applied manifest fixups for WebKit compatibility", category: Logger.extensions)
            } catch {
                Logger.error("Failed to write fixed manifest: \(error)", category: Logger.extensions)
            }
        }
    }

    /// Extracts the ZIP portion from a CRX3 file.
    ///
    /// CRX3 format:
    /// - 4 bytes: "Cr24" magic number
    /// - 4 bytes: version (3)
    /// - 4 bytes: header length (little-endian)
    /// - header_length bytes: protobuf header
    /// - remaining: ZIP data
    private nonisolated static func extractZipFromCRX(_ data: Data) throws -> Data {
        guard data.count > 12 else {
            throw ExtensionError.invalidArchiveFormat
        }

        // Check magic number "Cr24"
        let magic = String(data: data[0 ..< 4], encoding: .ascii)
        guard magic == "Cr24" else {
            throw ExtensionError.invalidArchiveFormat
        }

        // Check version (should be 3 for CRX3)
        let version = data[4 ..< 8].withUnsafeBytes { $0.load(as: UInt32.self) }
        guard version == 3 else {
            throw ExtensionError.invalidArchiveFormat
        }

        // Get header length
        let headerLength = data[8 ..< 12].withUnsafeBytes { $0.load(as: UInt32.self) }
        let zipStart = 12 + Int(headerLength)

        guard zipStart < data.count else {
            throw ExtensionError.invalidArchiveFormat
        }

        // Return ZIP portion
        return data[zipStart...]
    }

    /// Uninstalls an extension.
    ///
    /// This removes the extension from all controllers and cleans up
    /// extracted files for archive-based installations.
    ///
    /// - Parameter extension_: The extension to uninstall.
    func uninstall(_ extension_: InstalledExtension) async throws {
        // Unload from default controller
        if let context = loadedContexts[extension_.uniqueIdentifier] {
            try defaultController.unload(context)
            loadedContexts.removeValue(forKey: extension_.uniqueIdentifier)
        }

        // Unload from all isolated controllers
        for (key, context) in isolatedContexts where key.extensionIdentifier == extension_.uniqueIdentifier {
            if let controller = isolatedControllers[key.spaceID] {
                try controller.unload(context)
            }
        }
        isolatedContexts = isolatedContexts.filter { $0.key.extensionIdentifier != extension_.uniqueIdentifier }

        // Unload from all private controllers
        for (key, context) in privateContexts where key.extensionIdentifier == extension_.uniqueIdentifier {
            if let controller = privateControllers[key.spaceID] {
                try controller.unload(context)
            }
        }
        privateContexts = privateContexts.filter { $0.key.extensionIdentifier != extension_.uniqueIdentifier }

        // Unregister scripts
        state.scriptRegistry.unregisterExtension(extension_.uniqueIdentifier)

        // Remove extracted folder for archive-based installations
        switch extension_.source {
        case .crxFile, .xpiFile:
            let extractedDir = stateFileURL.deletingLastPathComponent()
                .appendingPathComponent("Extracted", isDirectory: true)
                .appendingPathComponent(extension_.uniqueIdentifier, isDirectory: true)
            try? FileManager.default.removeItem(at: extractedDir)
        default:
            break
        }

        // Remove from persisted state
        installedExtensions.removeAll { $0.id == extension_.id }
        savePersistedState()

        // Stop resource monitoring
        await resourceMonitor.stopMonitoring(for: extension_)

        // Clean up recovery state
        recoveryManager.extensionUninstalled(extension_)

        Logger.info("Uninstalled extension '\(extension_.displayName)'", category: Logger.extensions)
    }

    // MARK: - Enable/Disable

    /// Enables an installed extension.
    ///
    /// - Parameter extension_: The extension to enable.
    func enable(_ extension_: InstalledExtension) async throws {
        guard let index = installedExtensions.firstIndex(where: { $0.id == extension_.id }) else {
            throw ExtensionError.notInstalled
        }

        // Load the extension if not already loaded
        if loadedContexts[extension_.uniqueIdentifier] == nil {
            try await loadExtension(extension_)
        }

        installedExtensions[index].isEnabled = true
        savePersistedState()

        // Start resource monitoring
        await resourceMonitor.startMonitoring(for: extension_)

        // Reset crash state if user is manually re-enabling
        if recoveryManager.isDisabledDueToCrashes(extension_) {
            recoveryManager.resetCrashState(for: extension_)
        }

        Logger.info("Enabled extension '\(extension_.displayName)'", category: Logger.extensions)
    }

    /// Disables an installed extension.
    ///
    /// - Parameter extension_: The extension to disable.
    func disable(_ extension_: InstalledExtension) async throws {
        guard let index = installedExtensions.firstIndex(where: { $0.id == extension_.id }) else {
            throw ExtensionError.notInstalled
        }

        // Unload from default controller
        if let context = loadedContexts[extension_.uniqueIdentifier] {
            try defaultController.unload(context)
            loadedContexts.removeValue(forKey: extension_.uniqueIdentifier)
        }

        // Unload from all isolated controllers
        for (key, context) in isolatedContexts where key.extensionIdentifier == extension_.uniqueIdentifier {
            if let controller = isolatedControllers[key.spaceID] {
                try controller.unload(context)
            }
        }
        isolatedContexts = isolatedContexts.filter { $0.key.extensionIdentifier != extension_.uniqueIdentifier }

        // Unregister scripts
        state.scriptRegistry.unregisterExtension(extension_.uniqueIdentifier)

        installedExtensions[index].isEnabled = false
        savePersistedState()

        // Stop resource monitoring
        await resourceMonitor.stopMonitoring(for: extension_)

        Logger.info("Disabled extension '\(extension_.displayName)'", category: Logger.extensions)
    }

    // MARK: - Settings Modification

    /// Sets whether an extension is allowed in private mode.
    ///
    /// - Parameters:
    ///   - allowed: Whether to allow in private mode.
    ///   - extension_: The extension to modify.
    func setPrivateMode(_ allowed: Bool, for extension_: InstalledExtension) {
        guard let index = installedExtensions.firstIndex(where: { $0.id == extension_.id }) else {
            return
        }

        installedExtensions[index].allowedInPrivateMode = allowed
        savePersistedState()

        Logger.info(
            "Set private mode \(allowed ? "enabled" : "disabled") for '\(extension_.displayName)'",
            category: Logger.extensions,
        )
    }

    /// Sets the update behavior for an extension.
    ///
    /// - Parameters:
    ///   - behavior: The update behavior to set.
    ///   - extension_: The extension to modify.
    func setUpdateBehavior(_ behavior: UpdateBehavior, for extension_: InstalledExtension) {
        guard let index = installedExtensions.firstIndex(where: { $0.id == extension_.id }) else {
            return
        }

        installedExtensions[index].updateBehavior = behavior
        savePersistedState()

        Logger.info(
            "Set update behavior to '\(behavior.rawValue)' for '\(extension_.displayName)'",
            category: Logger.extensions,
        )
    }

    // MARK: - Extension Actions

    /// Triggers a page action for an extension.
    ///
    /// This is called when the user clicks an extension in the page menu.
    /// It triggers the extension's browser/page action, which may show a popup.
    ///
    /// - Parameters:
    ///   - extensionID: The unique identifier of the extension.
    ///   - webPage: The current web page, if any.
    func triggerPageAction(for extensionID: String, in webPage: WebPage?) async {
        guard let context = loadedContexts[extensionID] else {
            Logger.warning(
                "Cannot trigger action: extension '\(extensionID)' not loaded",
                category: Logger.extensions,
            )
            return
        }

        Logger.info(
            "Triggering page action for extension '\(extensionID)'",
            category: Logger.extensions,
        )

        // Get the tab if available
        var tab: (any WKWebExtensionTab)?
        if let webPage,
           let pagePool = state.pagePool {
            tab = extensionTab(for: webPage.tabPage, pagePool: pagePool)
        }

        // Perform the action - this will trigger the delegate callback if a popup is needed
        context.performAction(for: tab)
    }

    // MARK: - Tab/Window Adapter Access

    /// Gets or creates an extension tab adapter for a tab page.
    ///
    /// - Parameters:
    ///   - tabPage: The tab page to adapt.
    ///   - pagePool: The web page pool for WebView access.
    /// - Returns: The extension tab adapter.
    func extensionTab(for tabPage: TabPage, pagePool: WebPagePool) -> RefraxExtensionTab {
        if let existing = tabAdapters[tabPage.id] {
            return existing
        }

        let adapter = RefraxExtensionTab(tabPage: tabPage, pagePool: pagePool, manager: self)
        tabAdapters[tabPage.id] = adapter
        return adapter
    }

    /// Removes the tab adapter when a tab page is closed.
    ///
    /// - Parameter tabPage: The closed tab page.
    func removeTabAdapter(for tabPage: TabPage) {
        tabAdapters.removeValue(forKey: tabPage.id)
    }

    /// Gets or creates an extension window adapter.
    ///
    /// - Parameters:
    ///   - windowState: The window state to adapt.
    ///   - nsWindow: The underlying AppKit window.
    /// - Returns: The extension window adapter.
    func extensionWindow(for windowState: WindowState, nsWindow: NSWindow) -> RefraxExtensionWindow {
        let key = ObjectIdentifier(windowState)
        if let existing = windowAdapters[key] {
            return existing
        }

        let adapter = RefraxExtensionWindow(
            windowState: windowState,
            nsWindow: nsWindow,
            state: state,
            manager: self,
        )
        windowAdapters[key] = adapter
        return adapter
    }

    /// Removes the window adapter when a window closes.
    ///
    /// - Parameter windowState: The closed window's state.
    func removeWindowAdapter(for windowState: WindowState) {
        windowAdapters.removeValue(forKey: ObjectIdentifier(windowState))
    }

    // MARK: - Tab Event Dispatching

    /// Returns the appropriate controller for a tab based on its space.
    private func controller(for tab: Tab) -> WKWebExtensionController {
        guard let space = tab.space else {
            return defaultController
        }
        return controller(for: space)
    }

    /// Notifies extensions that a tab was opened.
    ///
    /// - Parameter tab: The opened tab.
    func dispatchTabOpened(_ tab: Tab) {
        guard let tabPage = tab.pages.first else { return }
        guard let pagePool = state.pagePool else { return }

        let extensionTab = extensionTab(for: tabPage, pagePool: pagePool)
        controller(for: tab).didOpenTab(extensionTab)
    }

    /// Notifies extensions that a tab was closed.
    ///
    /// - Parameters:
    ///   - tab: The closed tab.
    ///   - windowClosing: Whether the window is also closing.
    func dispatchTabClosed(_ tab: Tab, windowClosing: Bool) {
        guard let tabPage = tab.pages.first else { return }

        if let adapter = tabAdapters[tabPage.id] {
            controller(for: tab).didCloseTab(adapter, windowIsClosing: windowClosing)
            removeTabAdapter(for: tabPage)
        }
    }

    /// Notifies extensions that a tab was activated.
    ///
    /// - Parameters:
    ///   - tab: The activated tab.
    ///   - previous: The previously active tab, if any.
    func dispatchTabActivated(_ tab: Tab, previous: Tab?) {
        guard let tabPage = tab.pages.first else { return }
        guard let pagePool = state.pagePool else { return }

        let extensionTab = extensionTab(for: tabPage, pagePool: pagePool)
        let previousExtensionTab: RefraxExtensionTab? = {
            guard let previous, let page = previous.pages.first else { return nil }
            return tabAdapters[page.id]
        }()

        controller(for: tab).didActivateTab(extensionTab, previousActiveTab: previousExtensionTab)
    }

    /// Notifies extensions that a navigation committed.
    ///
    /// - Parameters:
    ///   - tabPage: The tab page that navigated.
    ///   - url: The committed URL.
    func dispatchNavigationCommitted(_ tabPage: TabPage, url _: URL) {
        guard let adapter = tabAdapters[tabPage.id] else { return }
        let controller = controller(for: tabPage)
        controller.didChangeTabProperties(.URL, for: adapter)
    }

    /// Notifies extensions that a tab was moved within or between windows.
    ///
    /// - Parameters:
    ///   - tab: The moved tab.
    ///   - fromIndex: The original index in the source window.
    ///   - oldWindow: The source window (nil if same window move).
    func dispatchTabMoved(_ tab: Tab, fromIndex: Int, oldWindow: RefraxExtensionWindow?) {
        guard let tabPage = tab.pages.first else { return }
        guard let pagePool = state.pagePool else { return }

        let extensionTab = extensionTab(for: tabPage, pagePool: pagePool)
        controller(for: tab).didMoveTab(extensionTab, from: fromIndex, in: oldWindow)
    }

    /// Notifies extensions that tab properties changed.
    ///
    /// - Parameters:
    ///   - properties: The properties that changed.
    ///   - tab: The tab whose properties changed.
    func dispatchTabPropertiesChanged(
        _ properties: WKWebExtension.TabChangedProperties,
        for tab: Tab,
    ) {
        guard let tabPage = tab.pages.first else { return }
        guard let adapter = tabAdapters[tabPage.id] else { return }
        controller(for: tab).didChangeTabProperties(properties, for: adapter)
    }

    /// Notifies extensions that loading state changed for a tab.
    ///
    /// - Parameter tabPage: The tab page whose loading state changed.
    func dispatchLoadingChanged(_ tabPage: TabPage) {
        guard let adapter = tabAdapters[tabPage.id] else { return }
        let controller = controller(for: tabPage)
        controller.didChangeTabProperties(.loading, for: adapter)
    }

    /// Notifies extensions that a tab's title changed.
    ///
    /// - Parameter tabPage: The tab page whose title changed.
    func dispatchTitleChanged(_ tabPage: TabPage) {
        guard let adapter = tabAdapters[tabPage.id] else { return }
        let controller = controller(for: tabPage)
        controller.didChangeTabProperties(.title, for: adapter)
    }

    /// Notifies extensions that a tab's pinned state changed.
    ///
    /// - Parameter tab: The tab whose pinned state changed.
    func dispatchPinnedChanged(_ tab: Tab) {
        guard let tabPage = tab.pages.first else { return }
        guard let adapter = tabAdapters[tabPage.id] else { return }
        controller(for: tab).didChangeTabProperties(.pinned, for: adapter)
    }

    /// Returns the appropriate controller for a tab page based on its owning tab's space.
    private func controller(for tabPage: TabPage) -> WKWebExtensionController {
        guard let tab = tabPage.tab, let space = tab.space else {
            return defaultController
        }
        return controller(for: space)
    }

    // MARK: - Enabled Extensions Query

    /// Extensions that are currently loaded and enabled.
    var enabledExtensions: [InstalledExtension] {
        installedExtensions.filter { $0.isEnabled && loadedContexts[$0.uniqueIdentifier] != nil }
    }

    /// Gets the context for an installed extension.
    ///
    /// - Parameter extension_: The installed extension.
    /// - Returns: The loaded context, or nil if not loaded.
    func context(for extension_: InstalledExtension) -> WKWebExtensionContext? {
        loadedContexts[extension_.uniqueIdentifier]
    }

    // MARK: - Per-Site Disable List

    /// Checks if an extension is disabled for a specific URL.
    ///
    /// Extensions can be disabled on specific domains via `InstalledExtension.disabledOnDomains`.
    /// This check should be performed before:
    /// - Injecting content scripts
    /// - Showing extension actions in the page menu
    /// - Responding to extension API calls for a tab
    ///
    /// - Parameters:
    ///   - extension_: The extension to check.
    ///   - url: The URL to check against.
    /// - Returns: `true` if the extension is disabled for this URL's domain.
    func isExtensionDisabled(_ extension_: InstalledExtension, for url: URL) -> Bool {
        guard let host = url.host else { return false }
        return isExtensionDisabled(extension_, forDomain: host)
    }

    /// Checks if an extension is disabled for a specific domain.
    ///
    /// - Parameters:
    ///   - extension_: The extension to check.
    ///   - domain: The domain to check (e.g., "example.com").
    /// - Returns: `true` if the extension is disabled for this domain.
    func isExtensionDisabled(_ extension_: InstalledExtension, forDomain domain: String) -> Bool {
        let lowercasedDomain = domain.lowercased()

        // Check exact domain match
        if extension_.disabledOnDomains.contains(lowercasedDomain) {
            return true
        }

        // Check if disabled on a parent domain (e.g., "sub.example.com" matches "example.com")
        for disabledDomain in extension_.disabledOnDomains {
            if lowercasedDomain.hasSuffix("." + disabledDomain) {
                return true
            }
        }

        return false
    }

    /// Returns extensions that are enabled for a specific URL.
    ///
    /// Filters out extensions that are:
    /// - Not globally enabled
    /// - Disabled for the URL's domain via per-site settings
    ///
    /// - Parameter url: The URL to check extensions for.
    /// - Returns: Array of extensions enabled for this URL.
    func enabledExtensions(for url: URL) -> [InstalledExtension] {
        enabledExtensions.filter { !isExtensionDisabled($0, for: url) }
    }

    // MARK: - Per-Site Settings

    /// Disables an extension for a specific domain.
    ///
    /// - Parameters:
    ///   - extension_: The extension to disable.
    ///   - domain: The domain to disable it on (e.g., "example.com").
    func disableExtension(_ extension_: InstalledExtension, onDomain domain: String) {
        guard let index = installedExtensions.firstIndex(where: { $0.id == extension_.id }) else {
            return
        }

        let normalizedDomain = domain.lowercased()
        installedExtensions[index].disabledOnDomains.insert(normalizedDomain)
        savePersistedState()

        Logger.info(
            "Disabled extension '\(extension_.displayName)' on domain '\(normalizedDomain)'",
            category: Logger.extensions,
        )
    }

    /// Enables an extension for a specific domain (removes it from the disabled list).
    ///
    /// - Parameters:
    ///   - extension_: The extension to enable.
    ///   - domain: The domain to enable it on.
    func enableExtension(_ extension_: InstalledExtension, onDomain domain: String) {
        guard let index = installedExtensions.firstIndex(where: { $0.id == extension_.id }) else {
            return
        }

        let normalizedDomain = domain.lowercased()
        installedExtensions[index].disabledOnDomains.remove(normalizedDomain)
        savePersistedState()

        Logger.info(
            "Enabled extension '\(extension_.displayName)' on domain '\(normalizedDomain)'",
            category: Logger.extensions,
        )
    }

    /// Toggles an extension's enabled state for a specific domain.
    ///
    /// - Parameters:
    ///   - extension_: The extension to toggle.
    ///   - domain: The domain to toggle on.
    ///   - enabled: Whether the extension should be enabled on this domain.
    func setExtensionEnabled(_ extension_: InstalledExtension, onDomain domain: String, enabled: Bool) {
        if enabled {
            enableExtension(extension_, onDomain: domain)
        } else {
            disableExtension(extension_, onDomain: domain)
        }
    }

    // MARK: - Private Helpers

    /// Loads an extension from its persisted state into the default controller.
    private func loadExtension(_ extension_: InstalledExtension) async throws {
        // Determine the folder URL based on source type
        let folderURL: URL

        switch extension_.source {
        case let .localFolder(url):
            folderURL = url

        case .crxFile, .xpiFile, .bundled:
            // Archive-based and bundled extensions are extracted to Extensions/Extracted/{uniqueIdentifier}/
            folderURL = extractedFolderURL(for: extension_)

        case .chromeWebStore, .firefoxAddons, .refraxGallery:
            // These would be downloaded and extracted - currently not fully implemented
            Logger.warning(
                "Web store extensions not yet supported for reload: \(extension_.displayName)",
                category: Logger.extensions,
            )
            throw ExtensionError.unsupportedSource
        }

        // Verify folder still exists
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            throw ExtensionError.sourceNotFound
        }

        let webExtension = try await WKWebExtension(resourceBaseURL: folderURL)
        let context = WKWebExtensionContext(for: webExtension)

        // Restore persisted permission state
        applyPersistedPermissions(to: context, from: extension_)

        // Enable Web Inspector for debug builds
        configureInspection(for: context)

        try defaultController.load(context)
        loadedContexts[extension_.uniqueIdentifier] = context

        // Configure shims after loading (webViewConfiguration is only available after load)
        shimInjector.configure(context: context)
    }

    /// Returns the extracted folder URL for an archive-based or bundled extension.
    ///
    /// - Parameter extension_: The installed extension.
    /// - Returns: The path to the extracted extension folder.
    private func extractedFolderURL(for extension_: InstalledExtension) -> URL {
        stateFileURL.deletingLastPathComponent()
            .appendingPathComponent("Extracted", isDirectory: true)
            .appendingPathComponent(extension_.uniqueIdentifier, isDirectory: true)
    }

    /// Loads an extension into a specific controller for an isolated or private space.
    ///
    /// - Parameters:
    ///   - extension_: The extension to load.
    ///   - controller: The controller to load into.
    ///   - spaceID: The space ID for tracking the context.
    ///   - isPrivate: Whether this is a private space (contexts stored differently).
    private func loadExtension(
        _ extension_: InstalledExtension,
        into controller: WKWebExtensionController,
        spaceID: UUID,
        isPrivate: Bool = false,
    ) async throws {
        // Determine the folder URL based on source type
        let folderURL: URL

        switch extension_.source {
        case let .localFolder(url):
            folderURL = url

        case .crxFile, .xpiFile, .bundled:
            folderURL = extractedFolderURL(for: extension_)

        case .chromeWebStore, .firefoxAddons, .refraxGallery:
            throw ExtensionError.unsupportedSource
        }

        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            throw ExtensionError.sourceNotFound
        }

        let webExtension = try await WKWebExtension(resourceBaseURL: folderURL)
        let context = WKWebExtensionContext(for: webExtension)

        // Apply persisted permissions to context (skip for private - they don't persist)
        if !isPrivate {
            applyPersistedPermissions(to: context, from: extension_)
        }

        // Enable Web Inspector for debug builds
        configureInspection(for: context)

        try controller.load(context)

        // Configure shims after loading (webViewConfiguration is only available after load)
        shimInjector.configure(context: context)

        let key = SpaceExtensionKey(spaceID: spaceID, extensionIdentifier: extension_.uniqueIdentifier)

        // Store in appropriate context dictionary
        if isPrivate {
            privateContexts[key] = context
        } else {
            isolatedContexts[key] = context
        }
    }

    // MARK: - Permission Restoration

    /// Applies persisted permissions to an extension context.
    ///
    /// This restores the permission state from the saved `InstalledExtension` to the
    /// newly created `WKWebExtensionContext`. Called when loading extensions on launch
    /// or when loading into isolated space controllers.
    ///
    /// Permissions with past expiration dates are skipped.
    ///
    /// - Parameters:
    ///   - context: The extension context to apply permissions to.
    ///   - extension_: The persisted extension metadata containing permission state.
    private func applyPersistedPermissions(
        to context: WKWebExtensionContext,
        from extension_: InstalledExtension,
    ) {
        let now = Date()

        // Apply granted permissions
        for (permissionString, expirationDate) in extension_.grantedPermissions {
            // Skip expired permissions
            guard expirationDate > now else { continue }

            let permission = WKWebExtension.Permission(rawValue: permissionString)
            context.setPermissionStatus(.grantedExplicitly, for: permission, expirationDate: expirationDate)
        }

        // Apply denied permissions
        for (permissionString, expirationDate) in extension_.deniedPermissions {
            guard expirationDate > now else { continue }

            let permission = WKWebExtension.Permission(rawValue: permissionString)
            context.setPermissionStatus(.deniedExplicitly, for: permission, expirationDate: expirationDate)
        }

        // Apply granted match patterns
        for (patternString, expirationDate) in extension_.grantedMatchPatterns {
            guard expirationDate > now else { continue }

            do {
                let pattern = try WKWebExtension.MatchPattern(string: patternString)
                context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: expirationDate)
            } catch {
                Logger.warning(
                    "Invalid match pattern '\(patternString)' for extension '\(extension_.displayName)'",
                    category: Logger.extensions,
                )
            }
        }

        // Apply denied match patterns
        for (patternString, expirationDate) in extension_.deniedMatchPatterns {
            guard expirationDate > now else { continue }

            do {
                let pattern = try WKWebExtension.MatchPattern(string: patternString)
                context.setPermissionStatus(.deniedExplicitly, for: pattern, expirationDate: expirationDate)
            } catch {
                Logger.warning(
                    "Invalid match pattern '\(patternString)' for extension '\(extension_.displayName)'",
                    category: Logger.extensions,
                )
            }
        }

        Logger.debug(
            "Restored permissions for extension '\(extension_.displayName)': " +
                "\(extension_.grantedPermissions.count) granted, " +
                "\(extension_.deniedPermissions.count) denied",
            category: Logger.extensions,
        )
    }

    /// Grants all requested permissions for a bundled extension.
    ///
    /// Bundled extensions are trusted and ship with the browser, so we auto-grant
    /// all permissions they request. This includes:
    /// - All manifest permissions (storage, tabs, webRequest, etc.)
    /// - All host permissions and match patterns (including `<all_urls>`)
    ///
    /// - Parameters:
    ///   - context: The extension context to grant permissions to.
    ///   - extension_: The WKWebExtension with manifest permissions.
    ///   - installedExtension: The installed extension metadata (updated with granted permissions).
    private func grantAllPermissions(
        for context: WKWebExtensionContext,
        extension_: WKWebExtension,
        installedExtension: inout InstalledExtension,
    ) {
        let permanentExpiration = Date.distantFuture

        // Grant all requested permissions from manifest
        for permission in extension_.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission, expirationDate: permanentExpiration)
            installedExtension.grantedPermissions[permission.rawValue] = permanentExpiration
        }

        // Grant all requested match patterns (host permissions)
        for pattern in extension_.requestedPermissionMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: permanentExpiration)
            installedExtension.grantedMatchPatterns[pattern.string] = permanentExpiration
        }

        // Also grant optional permissions that are commonly needed
        for permission in extension_.optionalPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission, expirationDate: permanentExpiration)
            installedExtension.grantedPermissions[permission.rawValue] = permanentExpiration
        }

        for pattern in extension_.optionalPermissionMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: permanentExpiration)
            installedExtension.grantedMatchPatterns[pattern.string] = permanentExpiration
        }

        Logger.info(
            "Auto-granted \(extension_.requestedPermissions.count) permissions and " +
                "\(extension_.requestedPermissionMatchPatterns.count) match patterns for bundled extension " +
                "'\(installedExtension.displayName)'",
            category: Logger.extensions,
        )
    }

    /// Updates installed extension metadata from a context.
    private func updateFromContext(
        _ extension_: InstalledExtension,
        context: WKWebExtensionContext,
    ) -> InstalledExtension {
        var updated = extension_
        updated.displayName = context.webExtension.displayName ?? extension_.displayName
        updated.version = context.webExtension.displayVersion ?? extension_.version
        updated.description = context.webExtension.displayDescription
        return updated
    }

    // MARK: - Web Inspector Integration

    /// Configures inspection settings for an extension context.
    ///
    /// In debug builds, enables Web Inspector for the extension's background page.
    /// This allows developers to debug extension scripts.
    ///
    /// - Parameter context: The extension context to configure.
    private func configureInspection(for context: WKWebExtensionContext) {
        #if DEBUG
            context.isInspectable = true
        #endif
    }

    /// Opens Web Inspector for an extension's background page.
    ///
    /// Only works in debug builds where `isInspectable` is enabled.
    /// Users should access the inspector via the Develop menu in the menu bar.
    ///
    /// - Parameter extension_: The extension to inspect.
    /// - Returns: `true` if the extension is inspectable, `false` otherwise.
    @discardableResult
    func inspectExtension(_ extension_: InstalledExtension) -> Bool {
        guard let context = loadedContexts[extension_.uniqueIdentifier] else {
            Logger.warning(
                "Cannot inspect extension '\(extension_.displayName)': not loaded",
                category: Logger.extensions,
            )
            return false
        }

        #if DEBUG
            // Context is already set as inspectable during load
            // User can inspect via: Develop > [Extension Name] > Background Page
            if context.isInspectable {
                Logger.info(
                    "Extension '\(extension_.displayName)' is inspectable. " +
                        "Use Develop menu > \(extension_.displayName) > Background Page",
                    category: Logger.extensions,
                )
                return true
            } else {
                Logger.warning(
                    "Extension '\(extension_.displayName)' is not inspectable",
                    category: Logger.extensions,
                )
                return false
            }
        #else
            Logger.info(
                "Web Inspector not available in release builds",
                category: Logger.extensions,
            )
            return false
        #endif
    }

    // MARK: - Resource Management

    /// Returns the current resource metrics for an extension.
    ///
    /// - Parameter extension_: The extension to get metrics for.
    /// - Returns: Current metrics, or nil if not being monitored.
    func resourceMetrics(for extension_: InstalledExtension) async -> ResourceMetrics? {
        await resourceMonitor.metrics(for: extension_)
    }

    /// Returns metrics for all enabled extensions.
    func allResourceMetrics() async -> [ResourceMetrics] {
        await resourceMonitor.allMetrics()
    }

    /// Notifies the resource monitor that the metrics UI has become visible or hidden.
    ///
    /// Call this when opening/closing extension settings or resource monitoring views.
    /// When visible, the monitor samples at 5-second intervals for responsive updates.
    /// When hidden, sampling is skipped to save CPU and battery.
    func setResourceMonitorUIVisibility(_ visible: Bool) async {
        await resourceMonitor.setUIVisibility(visible)
    }

    /// Starts observing app activation state to pause/resume resource monitoring.
    ///
    /// When the app is inactive AND the metrics UI is not visible, resource monitoring
    /// pauses entirely to save battery. This is called automatically when
    /// `activationObserver` is set.
    private func startAppActivationObservation(_ observer: AppActivationObserver) {
        activationObservationTask?.cancel()

        // Set initial state
        Task {
            await resourceMonitor.setAppActive(observer.isAppActive)
        }

        // Observe changes
        let activationChanges = Observations { observer.isAppActive }
        activationObservationTask = Task { [weak self] in
            for await isActive in activationChanges {
                guard let self, !Task.isCancelled else { break }
                await resourceMonitor.setAppActive(isActive)
            }
        }
    }

    /// Checks the budget status for an extension.
    ///
    /// - Parameter extension_: The extension to check.
    /// - Returns: The current budget status.
    func checkBudgetStatus(for extension_: InstalledExtension) async -> ExtensionResourceMonitor.BudgetStatus {
        await resourceMonitor.budgetStatus(for: extension_, budget: extension_.resourceBudget)
    }

    /// Checks budget status for all extensions and takes action on violations.
    ///
    /// Call this periodically to enforce resource limits. Extensions exceeding
    /// budgets will be warned or suspended.
    func enforceResourceBudgets() async {
        for installedExtension in enabledExtensions {
            let status = await resourceMonitor.budgetStatus(for: installedExtension)

            switch status {
            case .withinLimits:
                continue

            case let .warning(warning):
                // Log warning but don't take action yet
                recoveryManager.recordWarning(
                    "Resource usage warning: \(warning.resourceType.rawValue) at \(Int(warning.percentUsed * 100))% of budget",
                    for: installedExtension,
                )

            case let .exceeded(violation):
                // Suspend the extension
                Logger.warning(
                    "Extension '\(installedExtension.displayName)' exceeded \(violation.resourceType.rawValue) budget, suspending",
                    category: Logger.extensions,
                )

                recoveryManager.recordError(
                    ExtensionError.resourceBudgetExceeded(violation.resourceType.rawValue),
                    for: installedExtension,
                )

                do {
                    try await disable(installedExtension)
                } catch {
                    Logger.error(
                        "Failed to suspend extension '\(installedExtension.displayName)': \(error)",
                        category: Logger.extensions,
                    )
                }
            }
        }
    }

    /// Sets a custom resource budget for an extension.
    ///
    /// - Parameters:
    ///   - budget: The new budget, or nil to use default.
    ///   - extension_: The extension to update.
    func setResourceBudget(_ budget: ResourceBudget?, for extension_: InstalledExtension) {
        guard let index = installedExtensions.firstIndex(where: { $0.id == extension_.id }) else {
            return
        }

        installedExtensions[index].resourceBudget = budget
        savePersistedState()

        Logger.info(
            "Updated resource budget for '\(extension_.displayName)'",
            category: Logger.extensions,
        )
    }

    // MARK: - Update Management

    /// Checks for updates for a single extension.
    ///
    /// - Parameter extension_: The extension to check.
    /// - Returns: Information about the available update, if any.
    func checkForUpdate(_ extension_: InstalledExtension) async -> ExtensionUpdateChecker.UpdateInfo? {
        let result = await updateChecker.checkForUpdate(extension_)
        if case let .updateAvailable(info) = result {
            return info
        }
        return nil
    }

    /// Checks for updates for all installed extensions.
    ///
    /// - Returns: Dictionary of extension IDs to available update info.
    func checkAllForUpdates() async -> [UUID: ExtensionUpdateChecker.UpdateInfo] {
        let results = await updateChecker.checkAllForUpdates(installedExtensions)
        var updates: [UUID: ExtensionUpdateChecker.UpdateInfo] = [:]

        for (id, result) in results {
            if case let .updateAvailable(info) = result {
                updates[id] = info
            }
        }

        return updates
    }

    /// Returns pending updates that haven't been applied yet.
    var pendingUpdates: [UUID: ExtensionUpdateChecker.UpdateInfo] {
        get async {
            await updateChecker.pendingUpdates
        }
    }

    /// Applies an available update to an extension.
    ///
    /// Behavior depends on the extension's `updateBehavior`:
    /// - `.auto`: Downloads and applies immediately
    /// - `.notify`: Downloads, then sends notification for user confirmation
    /// - `.manual`: No automatic action
    ///
    /// - Parameter extension_: The extension to update.
    /// - Returns: `true` if update was applied, `false` if waiting for user action.
    func applyUpdate(for extension_: InstalledExtension) async throws -> Bool {
        try await updateChecker.applyUpdate(for: extension_)
    }

    /// Confirms and applies a pending update (for notify behavior).
    ///
    /// - Parameter extension_: The extension to update.
    func confirmUpdate(for extension_: InstalledExtension) async throws {
        try await updateChecker.confirmUpdate(for: extension_)
    }

    /// Dismisses a pending update notification.
    ///
    /// - Parameter extension_: The extension to dismiss the update for.
    func dismissUpdate(for extension_: InstalledExtension) async {
        await updateChecker.dismissUpdate(for: extension_)
    }

    // MARK: - Persistence

    /// Loads persisted extension state from disk.
    private func loadPersistedState() {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: stateFileURL)
            let store = try JSONDecoder().decode(ExtensionStateStore.self, from: data)
            installedExtensions = store.installedExtensions
            globalSettings = store.globalSettings
        } catch {
            Logger.error("Failed to load extension state: \(error)", category: Logger.extensions)
        }
    }

    /// Saves extension state to disk.
    private func savePersistedState() {
        let store = ExtensionStateStore(
            installedExtensions: installedExtensions,
            globalSettings: globalSettings,
            lastSyncDate: nil,
        )

        do {
            // Ensure directory exists
            let dir = stateFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let data = try JSONEncoder().encode(store)
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            Logger.error("Failed to save extension state: \(error)", category: Logger.extensions)
        }
    }
}

// MARK: - Extension Errors

/// Errors that can occur during extension operations.
enum ExtensionError: Error, LocalizedError {
    /// The extension manifest contains errors.
    case manifestErrors([String])

    /// The extension is not installed.
    case notInstalled

    /// The extension source type is not yet supported.
    case unsupportedSource

    /// The extension source file/folder was not found.
    case sourceNotFound

    /// Permission was denied for the operation.
    case permissionDenied

    /// The archive file is not a valid CRX or XPI format.
    case invalidArchiveFormat

    /// Failed to extract the extension archive.
    case extractionFailed

    /// Extension exceeded its resource budget.
    case resourceBudgetExceeded(String)

    /// The extension is already installed from this source.
    case alreadyInstalled

    /// Failed to download extension from web store.
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case let .manifestErrors(errors):
            "Extension manifest errors: \(errors.joined(separator: ", "))"
        case .notInstalled:
            "Extension is not installed"
        case .unsupportedSource:
            "Extension source type is not yet supported"
        case .sourceNotFound:
            "Extension source file or folder not found"
        case .permissionDenied:
            "Permission denied for extension operation"
        case .invalidArchiveFormat:
            "Invalid extension archive format"
        case .extractionFailed:
            "Failed to extract extension archive"
        case let .resourceBudgetExceeded(resource):
            "Extension exceeded \(resource) resource budget"
        case .alreadyInstalled:
            "This extension is already installed"
        case let .downloadFailed(reason):
            "Failed to download extension: \(reason)"
        }
    }
}

/// Web stores from which extensions can be installed.
enum WebStore: String, Sendable {
    case chrome
    case firefox
}
