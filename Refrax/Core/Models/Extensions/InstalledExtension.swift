import Foundation

/// Persisted metadata about an installed browser extension.
///
/// This is stored as JSON in Application Support for iCloud sync compatibility.
/// Not a SwiftData model - extension state is managed separately from browser data.
///
/// ## Persistence
///
/// Extensions are persisted to `~/Library/Application Support/Refrax/Extensions/`.
/// The JSON format allows easy iCloud sync of extension list and settings.
///
/// ## Runtime vs Persisted State
///
/// - **Persisted**: Installation source, enabled state, permissions, settings
/// - **Runtime**: `WKWebExtension`, `WKWebExtensionContext` - reconstructed on launch
nonisolated struct InstalledExtension: Codable, Identifiable, Hashable, Sendable {
    // MARK: - Identity

    /// Unique identifier for this installation.
    let id: UUID

    /// The extension's unique identifier from its manifest.
    ///
    /// This comes from `WKWebExtensionContext.uniqueIdentifier` and is stable
    /// across reinstalls of the same extension.
    let uniqueIdentifier: String

    /// Where the extension was installed from.
    let source: ExtensionSource

    /// When the extension was first installed.
    let installedAt: Date

    /// When the extension was last updated.
    var lastUpdated: Date

    // MARK: - State

    /// Whether the extension is currently enabled.
    var isEnabled: Bool

    /// Whether the extension is allowed in private browsing spaces.
    var allowedInPrivateMode: Bool

    /// How the extension should handle updates.
    var updateBehavior: UpdateBehavior

    // MARK: - Cached Manifest Info

    /// The extension's display name from manifest.
    var displayName: String

    /// The extension's version string.
    var version: String

    /// The manifest version (2 or 3).
    var manifestVersion: Double

    /// Cached icon data for UI display.
    var iconData: Data?

    /// Short description from manifest.
    var description: String?

    // MARK: - Permissions

    /// Permissions that have been granted, with expiration dates.
    ///
    /// Key is the permission string, value is when the grant expires (or `.distantFuture`
    /// for permanent grants).
    var grantedPermissions: [String: Date]

    /// Permissions that have been explicitly denied.
    var deniedPermissions: [String: Date]

    /// URL match patterns granted to the extension.
    var grantedMatchPatterns: [String: Date]

    /// URL match patterns explicitly denied.
    var deniedMatchPatterns: [String: Date]

    // MARK: - Per-Site Overrides

    /// Domains where this extension is disabled regardless of global state.
    var disabledOnDomains: Set<String>

    // MARK: - Resource Limits

    /// Optional resource budget override for this extension.
    var resourceBudget: ResourceBudget?

    // MARK: - Initialization

    /// Creates a new installed extension record.
    ///
    /// - Parameters:
    ///   - uniqueIdentifier: The extension's unique identifier from manifest.
    ///   - source: Where the extension was installed from.
    ///   - displayName: The extension's display name.
    ///   - version: The extension's version string.
    ///   - manifestVersion: The manifest version (2 or 3).
    init(
        uniqueIdentifier: String,
        source: ExtensionSource,
        displayName: String,
        version: String,
        manifestVersion: Double,
    ) {
        self.id = UUID()
        self.uniqueIdentifier = uniqueIdentifier
        self.source = source
        self.installedAt = Date()
        self.lastUpdated = Date()
        self.isEnabled = true
        self.allowedInPrivateMode = false
        self.updateBehavior = .notify
        self.displayName = displayName
        self.version = version
        self.manifestVersion = manifestVersion
        self.iconData = nil
        self.description = nil
        self.grantedPermissions = [:]
        self.deniedPermissions = [:]
        self.grantedMatchPatterns = [:]
        self.deniedMatchPatterns = [:]
        self.disabledOnDomains = []
        self.resourceBudget = nil
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: InstalledExtension, rhs: InstalledExtension) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Extension Source

/// Where an extension was installed from.
enum ExtensionSource: Codable, Hashable, Sendable {
    /// Local development folder.
    case localFolder(URL)

    /// Chrome .crx file.
    case crxFile(URL)

    /// Firefox .xpi file.
    case xpiFile(URL)

    /// Chrome Web Store by extension ID.
    case chromeWebStore(extensionID: String)

    /// Firefox Add-ons by extension ID.
    case firefoxAddons(extensionID: String)

    /// Refrax curated gallery by extension ID.
    case refraxGallery(extensionID: String)

    /// Bundled with the app (shipped in Resources).
    ///
    /// - Parameter name: The bundled extension identifier (e.g., "ublock-origin").
    case bundled(name: String)
}

// MARK: - Update Behavior

/// How an extension should handle available updates.
enum UpdateBehavior: String, Codable, Hashable, Sendable, CaseIterable {
    /// Download and apply updates automatically.
    case auto

    /// Download updates but prompt before applying.
    case notify

    /// User must manually trigger updates.
    case manual
}

// MARK: - Resource Budget

/// Resource limits for an extension.
struct ResourceBudget: Codable, Hashable, Sendable {
    /// Maximum memory usage in bytes.
    var maxMemory: UInt64

    /// Maximum sustained CPU usage (0-100).
    var maxCPU: Double

    /// Maximum network requests per minute.
    var maxNetworkRequestsPerMinute: Int

    /// Default budget for extensions.
    nonisolated static let `default` = ResourceBudget(
        maxMemory: 100 * 1_024 * 1_024, // 100MB
        maxCPU: 10.0, // 10%
        maxNetworkRequestsPerMinute: 100,
    )
}

// MARK: - Extension Global Settings

/// Global settings for extension management.
struct ExtensionGlobalSettings: Codable, Sendable, Equatable {
    /// Default update behavior for new extensions.
    var defaultUpdateBehavior: UpdateBehavior = .notify

    /// Whether extensions are allowed in private mode by default.
    var allowExtensionsInPrivateMode: Bool = false

    /// Whether resource monitoring is enabled.
    var resourceLimitsEnabled: Bool = true

    /// Default resource budget for new extensions.
    var defaultResourceBudget: ResourceBudget = .default

    /// Bundled extensions that have been installed.
    ///
    /// Tracks which bundled extensions have been auto-installed to avoid
    /// reinstalling on every launch. Key is the bundled name (e.g., "ublock-origin").
    var installedBundledExtensions: Set<String> = []
}

// MARK: - Extension State Store

/// Persisted state for all extensions.
///
/// Stored as JSON at `~/Library/Application Support/Refrax/Extensions/state.json`.
struct ExtensionStateStore: Codable, Sendable, Equatable {
    /// All installed extensions.
    var installedExtensions: [InstalledExtension]

    /// Global extension settings.
    var globalSettings: ExtensionGlobalSettings

    /// Last successful iCloud sync timestamp.
    var lastSyncDate: Date?

    /// Creates an empty state store.
    static let empty = ExtensionStateStore(
        installedExtensions: [],
        globalSettings: ExtensionGlobalSettings(),
        lastSyncDate: nil,
    )
}
