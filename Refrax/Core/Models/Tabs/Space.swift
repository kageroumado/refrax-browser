import Foundation
import SwiftData
import SwiftUI

/// A workspace containing tabs and groups.
///
/// Spaces provide isolated browsing contexts. Each space has its own set of tabs,
/// groups, and optionally an isolated website data store (cookies, cache, etc.).
///
/// ## Persistence
///
/// Space is a SwiftData model. All properties except those marked `@Transient`
/// are persisted to disk. The `tabs` and `groups` relationships are managed
/// automatically by SwiftData.
///
/// ## Reference Tabs
///
/// Reference tabs are tabs marked with `isReferenceTab = true`. They appear in
/// a side panel (max 4 per space). Access them via the `referenceTabs` computed
/// property which filters the `tabs` relationship.
///
/// ## Runtime State
///
/// Some properties are runtime-only (`@Transient`):
/// - `isLoaded`: Whether tabs have been loaded into memory
/// - `cachedColor`: Cached SwiftUI Color from hex string
@Model
final class Space {
    // MARK: - Identity

    /// Unique identifier for this space.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID

    // MARK: - Display

    /// Display name of the space.
    var name: String

    /// SF Symbol name or emoji character for the space icon.
    ///
    /// If the string is a single character that's an emoji, it's displayed as-is.
    /// Otherwise it's interpreted as an SF Symbol name.
    var iconName: String

    /// Optional description for the space.
    var spaceDescription: String?

    /// Hex color string for the space theme.
    ///
    /// Use the `color` computed property for SwiftUI Color access.
    var colorHex: String

    // MARK: - Organization

    /// Position in the space list (0-indexed).
    var position: Int

    /// When this space was created.
    var createdAt: Date

    // MARK: - Data Isolation

    /// The data storage mode for this space.
    ///
    /// Determines how browsing data (cookies, cache, localStorage, etc.) is stored:
    /// - `.global`: Shares data with other global-mode spaces (default)
    /// - `.separate`: Isolated persistent data store using space's UUID
    /// - `.private`: Non-persistent store, nothing written to disk
    ///
    /// - Important: This property is immutable after space creation.
    var dataStoreMode: DataStoreMode

    // MARK: - Downloads

    /// Custom download path for this space.
    ///
    /// When set, downloads in this space go to this directory instead of the global
    /// download location. Useful for organizing downloads by project/context.
    /// `nil` means use the global download path.
    var customDownloadPath: String?

    /// Finder color tag to apply to downloads from this space.
    ///
    /// Uses macOS Finder label colors (0-7):
    /// - 0: None
    /// - 1: Gray
    /// - 2: Green
    /// - 3: Purple
    /// - 4: Blue
    /// - 5: Yellow
    /// - 6: Red
    /// - 7: Orange
    ///
    /// `nil` means no color tag is applied.
    var downloadColorTag: Int?

    // MARK: - Security

    /// Whether this space requires Touch ID/password authentication to access.
    ///
    /// When enabled, the space content is hidden until the user authenticates.
    /// Authentication state is global across all windows.
    var isLockEnabled: Bool

    /// Custom auto-lock timeout in seconds for this space.
    ///
    /// Overrides the global `defaultLockTimeout` from `BrowserSettings`.
    /// `nil` means use the global default.
    var lockTimeoutOverride: Int?

    // MARK: - Relationships

    /// All tabs in this space.
    ///
    /// Includes both regular tabs and reference tabs. Use `mainTabs` and `referenceTabs`
    /// computed properties to filter by type.
    ///
    /// - Note: Delete rule is `.cascade` - deleting a space deletes all its tabs.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    @Relationship(deleteRule: .cascade, inverse: \Tab.space)
    var tabs: [Tab]

    /// All tab groups in this space.
    ///
    /// - Note: Delete rule is `.cascade` - deleting a space deletes all its groups.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    @Relationship(deleteRule: .cascade, inverse: \TabGroup.space)
    var groups: [TabGroup]

    // MARK: - Runtime State (Transient)

    /// Whether this space's tabs are currently loaded into memory.
    ///
    /// With SwiftData relationships, tabs are loaded automatically when accessed.
    /// This flag is kept for compatibility with existing code that checks load state.
    @Transient
    var isLoaded: Bool = false

    /// Cached SwiftUI color computed from hex string.
    @Transient
    private var cachedColor: Color?

    /// Cached sorted main tabs to avoid O(n log n) sort on every access.
    @Transient
    private var _mainTabsCache: [Tab]?

    /// Cached sorted reference tabs to avoid O(n log n) sort on every access.
    @Transient
    private var _referenceTabsCache: [Tab]?

    /// Tabs count when cache was created, for staleness detection.
    @Transient
    private var _tabsCacheCount: Int = -1

    // MARK: - Initialization

    /// Creates a new space.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Display name for the space.
    ///   - iconName: SF Symbol name or emoji character.
    ///   - colorHex: Color identifier — a ``GroupColor`` rawValue or tagged P3 string.
    ///   - position: Position in space list. Defaults to 0.
    ///   - dataStoreMode: The data storage mode. Defaults to `.global`.
    ///   - isLockEnabled: Whether the space requires authentication. Defaults to `false`.
    init(
        id: UUID = UUID(),
        name: String,
        iconName: String,
        colorHex: String = GroupColor.steel.rawValue,
        position: Int = 0,
        dataStoreMode: DataStoreMode = .global,
        isLockEnabled: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.spaceDescription = nil
        self.colorHex = colorHex
        self.position = position
        self.createdAt = Date()
        self.dataStoreMode = dataStoreMode
        self.customDownloadPath = nil
        self.downloadColorTag = nil
        self.isLockEnabled = isLockEnabled
        self.lockTimeoutOverride = nil
        self.tabs = []
        self.groups = []
    }

    /// Creates a new space with a SwiftUI Color.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Display name for the space.
    ///   - iconName: SF Symbol name or emoji character.
    ///   - color: Theme color. Defaults to blue.
    ///   - position: Position in space list. Defaults to 0.
    ///   - dataStoreMode: The data storage mode. Defaults to `.global`.
    ///   - isLockEnabled: Whether the space requires authentication. Defaults to `false`.
    @MainActor
    convenience init(
        id: UUID = UUID(),
        name: String,
        iconName: String,
        color: Color,
        position: Int = 0,
        dataStoreMode: DataStoreMode = .global,
        isLockEnabled: Bool = false,
    ) {
        self.init(
            id: id,
            name: name,
            iconName: iconName,
            colorHex: color.components.taggedString,
            position: position,
            dataStoreMode: dataStoreMode,
            isLockEnabled: isLockEnabled,
        )
    }

    // MARK: - Color Access

    /// SwiftUI Color representation of the space theme.
    ///
    /// Resolves `colorHex` as either a ``GroupColor`` name (adaptive asset catalog color)
    /// or a tagged P3/hex string (custom color). Cached for performance.
    @MainActor
    var color: Color {
        get {
            if let cached = cachedColor {
                return cached
            }
            let color = Color.resolveStoredColor(colorHex)
            cachedColor = color
            return color
        }
        set {
            colorHex = newValue.components.taggedString
            cachedColor = newValue
        }
    }

    // MARK: - Tab Access

    /// Main tabs (non-reference, non-archived tabs) sorted by position.
    ///
    /// Excludes archived tabs since they are non-activatable and displayed
    /// separately in the Archive group.
    ///
    /// Results are cached to avoid O(n log n) sort on every access.
    /// Cache is auto-invalidated when tabs count changes.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    var mainTabs: [Tab] {
        // Auto-invalidate cache if tabs count changed
        let currentCount = tabs.count
        if currentCount != _tabsCacheCount {
            _mainTabsCache = nil
            _referenceTabsCache = nil
        }
        if let cached = _mainTabsCache { return cached }
        let result = tabs.filter { !$0.isReferenceTab && !$0.isArchived }
            .sorted { $0.position < $1.position }
        _mainTabsCache = result
        _tabsCacheCount = tabs.count // Update count AFTER building cache
        return result
    }

    /// Reference pane tabs sorted by position.
    ///
    /// Maximum 4 reference tabs per space. Excludes archived tabs.
    ///
    /// Results are cached. Cache is auto-invalidated when tabs count changes.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    var referenceTabs: [Tab] {
        // Auto-invalidate cache if tabs count changed
        let currentCount = tabs.count
        if currentCount != _tabsCacheCount {
            _mainTabsCache = nil
            _referenceTabsCache = nil
        }
        if let cached = _referenceTabsCache { return cached }
        let result = tabs.filter { $0.isReferenceTab && !$0.isArchived }
            .sorted { $0.position < $1.position }
        _referenceTabsCache = result
        _tabsCacheCount = tabs.count // Update count AFTER building cache
        return result
    }

    /// Pinned tabs sorted by position.
    ///
    /// Uses cached `mainTabs` - already sorted by position.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    var pinnedTabs: [Tab] {
        mainTabs.filter(\.isPinned)
    }

    /// Unpinned tabs sorted by position.
    ///
    /// Uses cached `mainTabs` - already sorted by position.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    var unpinnedTabs: [Tab] {
        mainTabs.filter { !$0.isPinned }
    }

    /// Total number of main tabs.
    ///
    /// Uses cached count to avoid filtering on every access.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    var tabCount: Int {
        mainTabs.count
    }

    /// Number of reference tabs.
    ///
    /// Uses cached count to avoid filtering on every access.
    /// - Warning: Avoid reading this value from SwiftUI to avoid creating an observation dependency.
    var referenceTabCount: Int {
        referenceTabs.count
    }

    /// Invalidates the cached tab arrays.
    ///
    /// Call this when a tab's `position`, `isReferenceTab`, or `isArchived` property changes.
    /// Note: Cache is auto-invalidated when tabs are added/removed (count change detection).
    func invalidateTabCaches() {
        _mainTabsCache = nil
        _referenceTabsCache = nil
        _tabsCacheCount = -1
    }

    // MARK: - Icon Type

    /// Whether the icon is an emoji (single character) vs SF Symbol.
    var isEmoji: Bool {
        guard iconName.count == 1 else { return false }
        return iconName.unicodeScalars.first?.properties.isEmoji ?? false
    }

    /// The display name with emoji prefix if the icon is an emoji.
    var displayNameWithIcon: String {
        if isEmoji {
            return "\(iconName) \(name)"
        }
        return name
    }
}
