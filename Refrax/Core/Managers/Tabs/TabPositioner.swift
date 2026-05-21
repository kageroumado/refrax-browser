import Foundation

/// Handles position arithmetic and normalization for tabs and groups.
///
/// `TabPositioner` centralizes all position-related logic, providing:
/// - Insertion position calculation (append, after active, etc.)
/// - Hierarchical position normalization
/// - Position validation and conflict detection
///
/// ## Position Scheme
///
/// Positions use a hierarchical scheme to maintain visual order:
/// - Root level: billions (1_000_000_000 * index)
/// - In group: millions (base + 1_000_000 * offset)
/// - In nested group: thousands (base + 1_000 * offset)
///
/// This allows inserting items between existing items without renumbering,
/// while normalization can be deferred until necessary.
///
/// ## Usage
///
/// ```swift
/// let positioner = TabPositioner()
///
/// // Get insertion position for a new tab
/// let position = positioner.insertionPosition(for: space, isPinned: false, strategy: .append)
///
/// // Normalize after structural changes
/// positioner.normalizeIfNeeded(space: space, force: false)
/// ```
struct TabPositioner {
    // MARK: - Position Multipliers

    /// Position multiplier for root level items.
    static let rootMultiplier = 1_000_000_000

    /// Position multiplier for items in a group.
    static let groupMultiplier = 1_000_000

    /// Position multiplier for items in a nested group.
    static let nestedGroupMultiplier = 1_000

    // MARK: - Insertion Strategy

    /// Strategy for determining where to insert a new item.
    enum InsertionStrategy {
        /// Prepend at the beginning of the relevant section (below pinned for unpinned tabs).
        case prepend

        /// Append at the end of the relevant section (pinned or unpinned).
        case append

        /// Insert after the currently active tab (if applicable).
        case afterActive

        /// Insert at a specific position.
        case atPosition(Int)

        /// Force normalization and insert at the calculated position.
        case forceNormalize
    }

    // MARK: - Insertion Position

    /// Calculates the insertion position for a new tab.
    ///
    /// - Parameters:
    ///   - space: The space to insert into.
    ///   - isPinned: Whether the tab will be pinned.
    ///   - groupID: Optional group to insert into.
    ///   - strategy: The insertion strategy to use.
    ///   - activeTabID: The currently active tab ID (for `.afterActive` strategy).
    /// - Returns: The calculated position and array index.
    func insertionPosition(
        for space: Space,
        isPinned: Bool,
        groupID: UUID? = nil,
        strategy: InsertionStrategy = .prepend,
        activeTabID: UUID? = nil,
    ) -> (position: Int, index: Int) {
        switch strategy {
        case .prepend:
            return prependPosition(in: space, isPinned: isPinned, groupID: groupID)

        case .append:
            return appendPosition(in: space, isPinned: isPinned, groupID: groupID)

        case .afterActive:
            if let activeTabID,
               let activeIndex = space.tabs.firstIndex(where: { $0.id == activeTabID }) {
                let activeTab = space.tabs[activeIndex]
                let newIndex = activeIndex + 1
                let newPosition = activeTab.position + Self.groupMultiplier / 2
                return (newPosition, newIndex)
            }
            return appendPosition(in: space, isPinned: isPinned, groupID: groupID)

        case let .atPosition(position):
            let index = space.tabs.firstIndex { $0.position >= position } ?? space.tabs.count
            return (position, index)

        case .forceNormalize:
            let result = appendPosition(in: space, isPinned: isPinned, groupID: groupID)
            return result
        }
    }

    /// Calculates append position at the end of a section.
    private func appendPosition(in space: Space, isPinned: Bool, groupID: UUID?) -> (position: Int, index: Int) {
        if isPinned {
            let pinnedTabs = space.tabs.filter(\.isPinned)
            let index = pinnedTabs.count
            let position: Int = if let lastPinned = pinnedTabs.last {
                lastPinned.position + Self.rootMultiplier
            } else {
                Self.rootMultiplier
            }
            return (position, index)
        }

        if let groupID {
            let groupTabs = space.tabs.filter { $0.groupID == groupID }
            if let group = space.groups.first(where: { $0.id == groupID }) {
                let basePosition = group.position
                let offset = groupTabs.count + 1
                let position = basePosition + (offset * Self.groupMultiplier)
                let insertIndex = space.tabs.lastIndex(where: { $0.groupID == groupID })
                    .map { $0 + 1 } ?? space.tabs.count
                return (position, insertIndex)
            }
        }

        let index = space.tabs.count
        let position: Int = if let lastTab = space.tabs.last {
            lastTab.position + Self.rootMultiplier
        } else {
            Self.rootMultiplier
        }
        return (position, index)
    }

    /// Calculates prepend position at the beginning of a section.
    ///
    /// For unpinned tabs, this inserts at the top of the list (right after pinned tabs).
    /// This matches Arc's behavior where new tabs appear at the top of the tab list.
    private func prependPosition(in space: Space, isPinned: Bool, groupID: UUID?) -> (position: Int, index: Int) {
        if isPinned {
            // For pinned tabs, prepend means position 0 (before all pinned)
            let pinnedTabs = space.tabs.filter(\.isPinned)
            let index = 0
            let position: Int = if let firstPinned = pinnedTabs.first {
                firstPinned.position / 2
            } else {
                Self.rootMultiplier
            }
            return (position, index)
        }

        if let groupID {
            // For grouped tabs, prepend to the beginning of the group
            let groupTabs = space.tabs.filter { $0.groupID == groupID }
            if let group = space.groups.first(where: { $0.id == groupID }) {
                let basePosition = group.position
                let position: Int = if let firstInGroup = groupTabs.first {
                    // Insert before the first tab in group
                    basePosition + (basePosition + firstInGroup.position) / 2 - basePosition
                } else {
                    // Empty group, use first position
                    basePosition + Self.groupMultiplier
                }
                let insertIndex = space.tabs.firstIndex(where: { $0.groupID == groupID }) ?? space.tabs.count
                return (position, insertIndex)
            }
        }

        // For regular unpinned tabs, insert at the top (right after pinned section)
        let pinnedCount = space.pinnedTabs.count
        let unpinnedTabs = space.unpinnedTabs.filter { $0.groupID == nil }
            .sorted { $0.position < $1.position }

        let index = pinnedCount
        let position: Int = if let firstUnpinned = unpinnedTabs.first {
            // Insert before the first unpinned tab
            // Use half of the first unpinned position to leave room
            firstUnpinned.position / 2
        } else {
            // No unpinned tabs yet, use root multiplier
            Self.rootMultiplier
        }
        return (position, index)
    }

    // MARK: - Position Normalization

    /// Normalizes positions for tabs and groups to maintain visual order.
    ///
    /// Uses a hierarchical position scheme:
    /// - Root level: billions (1_000_000_000 * index)
    /// - In group: millions (base + 1_000_000 * offset)
    /// - In nested group: thousands (base + 1_000 * offset)
    ///
    /// - Parameters:
    ///   - space: Space to normalize.
    ///   - force: If true, always normalizes. If false, only normalizes if needed.
    /// - Returns: True if normalization was performed.
    @discardableResult
    func normalize(space: Space, force: Bool = false) -> Bool {
        if !force, !needsNormalization(space: space) {
            return false
        }

        performNormalization(space: space)
        return true
    }

    /// Checks if a space needs position normalization.
    ///
    /// Normalization is needed when:
    /// - Position values are not in ascending order
    /// - Gaps between positions are too small for insertion
    /// - Position values exceed safe integer bounds
    func needsNormalization(space: Space) -> Bool {
        let sortedTabs = space.tabs.sorted { $0.position < $1.position }

        for (index, tab) in space.tabs.enumerated() {
            if index < sortedTabs.count, sortedTabs[index].id != tab.id {
                return true
            }
        }

        if let lastPosition = space.tabs.last?.position,
           lastPosition > Int.max / 2 {
            return true
        }

        return false
    }

    /// Performs the actual normalization.
    private func performNormalization(space: Space) {
        var tabsByGroup: [UUID: [Tab]] = [:]
        var rootItems: [RootItem] = []

        // Only normalize main tabs, not reference tabs (which have their own simple 0-based indexing)
        for tab in space.tabs where !tab.isReferenceTab {
            if let groupID = tab.groupID {
                tabsByGroup[groupID, default: []].append(tab)
            } else {
                rootItems.append(.tab(tab))
            }
        }

        for (groupID, tabs) in tabsByGroup {
            tabsByGroup[groupID] = tabs.sorted { $0.position < $1.position }
        }

        var nestedGroupsByParent: [UUID: [TabGroup]] = [:]
        for group in space.groups {
            if let parentID = group.parentGroupID {
                nestedGroupsByParent[parentID, default: []].append(group)
            } else {
                rootItems.append(.group(group))
            }
        }

        rootItems.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.position < rhs.position
        }

        for (parentID, nested) in nestedGroupsByParent {
            nestedGroupsByParent[parentID] = nested.sorted { $0.position < $1.position }
        }

        var currentRootIndex = 1

        for rootItem in rootItems {
            switch rootItem {
            case let .group(group):
                processGroupPositions(
                    group,
                    basePosition: currentRootIndex * Self.rootMultiplier,
                    multiplier: Self.groupMultiplier,
                    tabsByGroup: tabsByGroup,
                    nestedGroupsByParent: nestedGroupsByParent,
                )
            case let .tab(tab):
                tab.position = currentRootIndex * Self.rootMultiplier
            }
            currentRootIndex += 1
        }
    }

    /// Type-safe representation of a root-level item (tab or group).
    private enum RootItem {
        case tab(Tab)
        case group(TabGroup)

        var position: Int {
            switch self {
            case let .tab(tab): tab.position
            case let .group(group): group.position
            }
        }

        var isPinned: Bool {
            switch self {
            case let .tab(tab): tab.isPinned
            case let .group(group): group.isPinned
            }
        }
    }

    /// Processes positions for a group and its contents recursively.
    private func processGroupPositions(
        _ group: TabGroup,
        basePosition: Int,
        multiplier: Int,
        tabsByGroup: [UUID: [Tab]],
        nestedGroupsByParent: [UUID: [TabGroup]],
    ) {
        group.position = basePosition
        var currentOffset = 1

        if let groupedTabs = tabsByGroup[group.id] {
            for tab in groupedTabs {
                tab.position = basePosition + (currentOffset * multiplier)
                currentOffset += 1
            }
        }

        if let nestedGroups = nestedGroupsByParent[group.id] {
            for nestedGroup in nestedGroups {
                let nestedBase = basePosition + (currentOffset * multiplier)
                processGroupPositions(
                    nestedGroup,
                    basePosition: nestedBase,
                    multiplier: multiplier / 1_000,
                    tabsByGroup: tabsByGroup,
                    nestedGroupsByParent: nestedGroupsByParent,
                )
                let nestedTabCount = tabsByGroup[nestedGroup.id]?.count ?? 0
                currentOffset += 1 + nestedTabCount
            }
        }
    }

    // MARK: - Position Utilities

    /// Returns the multiplier for a given nesting level.
    ///
    /// - Parameter level: The nesting level (0 = root, 1 = in group, 2 = in nested group).
    /// - Returns: The position multiplier for that level.
    func multiplier(forLevel level: Int) -> Int {
        switch level {
        case 0: Self.rootMultiplier
        case 1: Self.groupMultiplier
        case 2: Self.nestedGroupMultiplier
        default: Self.rootMultiplier
        }
    }

    /// Calculates a position between two existing positions.
    ///
    /// - Parameters:
    ///   - before: Position of the item before (or 0 if inserting at start).
    ///   - after: Position of the item after (or Int.max if inserting at end).
    /// - Returns: A position value between the two.
    func positionBetween(before: Int, after: Int) -> Int {
        guard before < after else { return before + 1 }

        let gap = after - before
        if gap > 1 {
            return before + gap / 2
        }
        return before + 1
    }

    /// Validates that positions in a space are in proper order.
    ///
    /// - Parameter space: The space to validate.
    /// - Returns: True if positions are valid, false if normalization is needed.
    func validatePositions(in space: Space) -> Bool {
        var lastPinnedPosition = Int.min
        var lastUnpinnedPosition = Int.min

        for tab in space.tabs.sorted(by: { $0.position < $1.position }) {
            if tab.isPinned {
                if tab.position <= lastPinnedPosition {
                    return false
                }
                lastPinnedPosition = tab.position
            } else {
                if tab.position <= lastUnpinnedPosition {
                    return false
                }
                lastUnpinnedPosition = tab.position
            }
        }

        return true
    }
}
