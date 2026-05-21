import Foundation
import SwiftData
import SwiftUI

/// Represents a collapsible folder for organizing tabs within a space
///
/// Tab groups provide hierarchical organization with support for:
/// - Collapsible headers with custom colors and icons
/// - Up to 2 levels of nesting (groups within groups)
/// - Pin support (groups can be pinned like tabs)
/// - Per-space isolation (each space has its own groups)
///
/// ## Hierarchy
/// - Root groups: `parentGroupID == nil`
/// - Nested groups: `parentGroupID == parent.id` (max 2 levels)
/// - Tabs reference groups via `Tab.groupID`
@Model
final class TabGroup {
    #Index<TabGroup>([\.parentGroupID])

    // MARK: - Properties

    /// Unique identifier for the group
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID

    /// The space containing this group.
    var space: Space?
    
    /// Parent group for nesting (nil for root-level groups)
    var parentGroupID: UUID?

    /// Display name of the group
    var name: String

    /// Color identifier for the group tint.
    ///
    /// Stores either a ``GroupColor`` rawValue (e.g. `"Steel"`) for palette colors,
    /// or a tagged P3 string (e.g. `"p3:0.5,0.3,0.8"`) for custom colors.
    var colorString: String {
        didSet {
            cachedColor = nil
        }
    }

    /// SF Symbol icon name
    var iconName: String?

    /// Position in the tab list (alongside tabs)
    var position: Int
    
    /// Whether the group is pinned (like pinned tabs)
    var isPinned: Bool

    /// Whether the group is collapsed in the sidebar
    var isCollapsed: Bool

    /// Whether this is the special Archive group for the space.
    ///
    /// Archive groups have restricted behavior:
    /// - Cannot be nested, pinned, or converted to favorites
    /// - Cannot be dragged (always positioned at bottom)
    /// - Tabs dragged out are automatically restored
    /// - Tabs dragged in are automatically archived
    ///
    /// Each space has at most one archive group, created on-demand when
    /// the first tab is archived.
    var isArchive: Bool

    /// Timestamp when group was created
    var createdAt: Date

    /// Associated tabs in this group (logical relationship only)
    @Relationship(deleteRule: .nullify, inverse: \Tab.group)
    var tabs: [Tab]
    
    /// Cached SwiftUI color (computed from hex string)
    ///
    /// This is not persisted - the hex string is the source of truth.
    /// Performance: ~1000ns to parse hex, cached after first access.
    @Transient
    private var cachedColor: Color?

    /// Cached sorted tabs to avoid O(n log n) sort on every access.
    @Transient
    private var _sortedTabsCache: [Tab]?

    /// Tabs count when cache was created, for staleness detection.
    @Transient
    private var _tabsCacheCount: Int = -1

    @MainActor
    var color: Color {
        get {
            if let cached = cachedColor {
                return cached
            }
            let color = Color.resolveStoredColor(colorString)
            cachedColor = color
            return color
        }
        set {
            colorString = newValue.components.taggedString
            cachedColor = newValue
        }
    }
    
    // MARK: - Initialization

    /// Initialize a new tab group.
    ///
    /// - Parameters:
    ///   - space: The space this group belongs to.
    ///   - name: The name of the group.
    ///   - color: Color identifier — a ``GroupColor`` rawValue or tagged P3 string.
    ///   - iconName: SF Symbol name (optional).
    ///   - parentGroupID: Parent group ID for nesting (optional).
    ///   - position: Position in the tab list (defaults to 0).
    ///   - isPinned: Whether the group is pinned (defaults to false).
    ///   - isCollapsed: Whether the group starts collapsed (defaults to false).
    ///   - isArchive: Whether this is the special Archive group (defaults to false).
    init(
        space: Space,
        name: String,
        color: String = GroupColor.steel.rawValue,
        iconName: String? = nil,
        parentGroupID: UUID? = nil,
        position: Int = 0,
        isPinned: Bool = false,
        isCollapsed: Bool = false,
        isArchive: Bool = false,
    ) {
        self.id = UUID()
        self.space = space
        self.parentGroupID = parentGroupID
        self.name = name
        self.colorString = color
        self.iconName = iconName
        self.position = position
        self.isPinned = isPinned
        self.isCollapsed = isCollapsed
        self.isArchive = isArchive
        self.createdAt = Date()
        self.tabs = []
    }

    // MARK: - Computed Properties

    /// Number of tabs in the group
    var tabCount: Int {
        tabs.count
    }

    /// Whether the group has any tabs
    var hasTabs: Bool {
        !tabs.isEmpty
    }

    /// Sorted tabs by position.
    ///
    /// Results are cached to avoid O(n log n) sort on every access.
    /// Cache is auto-invalidated when tabs count changes.
    var sortedTabs: [Tab] {
        // Auto-invalidate cache if tabs count changed
        if tabs.count != _tabsCacheCount {
            _sortedTabsCache = nil
            _tabsCacheCount = tabs.count
        }
        if let cached = _sortedTabsCache { return cached }
        let result = tabs.sorted { $0.position < $1.position }
        _sortedTabsCache = result
        return result
    }

    /// Invalidates the cached sorted tabs array.
    ///
    /// Call this when tab positions change (count changes are auto-detected).
    func invalidateTabCache() {
        _sortedTabsCache = nil
        _tabsCacheCount = -1
    }
    
    /// Whether this is a root-level group (not nested).
    var isRoot: Bool {
        parentGroupID == nil
    }
    
    /// Nesting depth (0 for root, 1 for nested)
    var nestingLevel: Int {
        parentGroupID == nil ? 0 : 1
    }

    /// Whether the icon is an emoji rather than an SF Symbol.
    var isEmoji: Bool {
        guard let icon = iconName, !icon.isEmpty else { return false }
        return icon.unicodeScalars.first?.properties.isEmoji ?? false
    }

    /// The display name with emoji prefix if the icon is an emoji.
    var displayNameWithIcon: String {
        if isEmoji, let icon = iconName {
            return "\(icon) \(name)"
        }
        return name
    }

    // MARK: - Methods

    // MARK: Internal Mutation Methods

    // These methods should only be called from TabManager/TabGroupManager.
    // External code should use TabManager.addTabToGroup() / TabGroupManager.removeTabFromGroup() etc.

    /// Add a tab to the group.
    ///
    /// - Parameter tab: The tab to add.
    ///
    /// - Important: Internal use only. Call ``TabManager/addTabToGroup(_:groupID:)``
    ///   to ensure proper state synchronization and undo support.
    func _addTab(_ tab: Tab) {
        tab.groupID = id
        tab.group = self
        tabs.append(tab)
    }

    /// Remove a tab from the group.
    ///
    /// - Parameter tab: The tab to remove.
    ///
    /// - Important: Internal use only. Call ``TabGroupManager/removeTabFromGroup(tab:groupID:)``
    ///   to ensure proper state synchronization and undo support.
    func _removeTab(_ tab: Tab) {
        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)
            tab.groupID = nil
            tab.group = nil
        }
    }

    /// Toggle collapsed state.
    ///
    /// - Important: Internal use only. Call ``TabGroupManager/toggleGroupCollapsed(_:)``
    ///   to ensure proper state synchronization.
    func _toggleCollapsed() {
        isCollapsed.toggle()
    }
}

// MARK: - Default Groups

extension TabGroup {
    /// Create a default "Work" group.
    ///
    /// - Parameter space: The space to create the group in.
    static func defaultWorkGroup(in space: Space) -> TabGroup {
        TabGroup(
            space: space,
            name: "Work",
            color: GroupColor.steel.rawValue,
            iconName: "briefcase.fill",
            position: 0,
        )
    }

    /// - Parameter space: The space to create the group in.
    static func defaultPersonalGroup(in space: Space) -> TabGroup {
        TabGroup(
            space: space,
            name: "Personal",
            color: GroupColor.emerald.rawValue,
            iconName: "house.fill",
            position: 1,
        )
    }
}
