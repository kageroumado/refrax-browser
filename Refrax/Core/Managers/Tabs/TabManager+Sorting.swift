import Foundation

// MARK: - Tab Sorting

extension TabManager {
    /// Sorts all tabs and groups in a space by the given criterion.
    ///
    /// This is a one-time operation that updates `position` values to reflect
    /// the new order. The sort is performed separately on:
    /// - Pinned items (tabs and groups)
    /// - Unpinned items (tabs and groups)
    ///
    /// Groups are sorted by their own properties (name for alphabetical sorts,
    /// `createdAt` for date sorts). Tabs within groups are also sorted.
    ///
    /// - Parameters:
    ///   - criterion: The sort criterion to apply.
    ///   - space: The space containing tabs to sort.
    func sortTabs(by criterion: TabSortCriterion, in space: Space) {
        spaceManager.ensureLoaded(space)

        // Pre-build indexes for O(1) lookups throughout sorting
        let tabIndex = Dictionary(uniqueKeysWithValues: space.tabs.map { ($0.id, $0) })
        let groupIndex = Dictionary(uniqueKeysWithValues: space.groups.map { ($0.id, $0) })
        let tabsByGroupID = Dictionary(grouping: space.tabs, by: { $0.groupID })
        let groupsByParentID = Dictionary(grouping: space.groups, by: { $0.parentGroupID })

        sortRootLevelItems(
            by: criterion,
            in: space,
            isPinned: true,
            tabIndex: tabIndex,
            groupIndex: groupIndex,
        )
        sortRootLevelItems(
            by: criterion,
            in: space,
            isPinned: false,
            tabIndex: tabIndex,
            groupIndex: groupIndex,
        )

        for group in space.groups {
            sortTabsInGroup(
                group,
                by: criterion,
                tabsByGroupID: tabsByGroupID,
                groupsByParentID: groupsByParentID,
            )
        }

        normalizePositions(in: space)
        state.incrementListVersion()
        scheduleSave()

        Logger.info("Sorted tabs by \(criterion.displayName) in \(space.name)", category: Logger.tabs)
    }

    /// Sorts root-level items (ungrouped tabs and root groups) within a pinned/unpinned section.
    private func sortRootLevelItems(
        by criterion: TabSortCriterion,
        in space: Space,
        isPinned: Bool,
        tabIndex: [UUID: Tab],
        groupIndex: [UUID: TabGroup],
    ) {
        var ungroupedTabs = space.tabs.filter { $0.groupID == nil && $0.isPinned == isPinned }
        var rootGroups = space.groups.filter { $0.parentGroupID == nil && $0.isPinned == isPinned }

        ungroupedTabs.sort { compareTabs($0, $1, by: criterion) }
        rootGroups.sort { compareGroups($0, $1, by: criterion) }

        var allItems: [(id: UUID, isGroup: Bool)] = []
        allItems += ungroupedTabs.map { ($0.id, false) }
        allItems += rootGroups.map { ($0.id, true) }

        // Pre-compute sort keys before sorting to avoid repeated lookups in comparator
        var sortKeys: [UUID: SortKey] = [:]
        for item in allItems {
            if item.isGroup, let group = groupIndex[item.id] {
                sortKeys[item.id] = sortKeyForGroup(group, criterion: criterion)
            } else if let tab = tabIndex[item.id] {
                sortKeys[item.id] = sortKeyForTab(tab, criterion: criterion)
            }
        }

        allItems.sort { lhs, rhs in
            let lhsSortKey = sortKeys[lhs.id] ?? .fallback
            let rhsSortKey = sortKeys[rhs.id] ?? .fallback
            return compareSortKeys(lhsSortKey, rhsSortKey, criterion: criterion)
        }

        // Assign positions using pre-built indexes
        let basePosition = isPinned ? 0 : 1_000_000
        for (index, item) in allItems.enumerated() {
            let newPosition = basePosition + index
            if item.isGroup {
                groupIndex[item.id]?.position = newPosition
            } else {
                tabIndex[item.id]?.position = newPosition
            }
        }
    }

    /// Sorts tabs within a specific group using pre-built indexes.
    private func sortTabsInGroup(
        _ group: TabGroup,
        by criterion: TabSortCriterion,
        tabsByGroupID: [UUID?: [Tab]],
        groupsByParentID: [UUID?: [TabGroup]],
    ) {
        var groupTabs = tabsByGroupID[group.id] ?? []
        groupTabs.sort { compareTabs($0, $1, by: criterion) }

        for (index, tab) in groupTabs.enumerated() {
            tab.position = group.position + index + 1
        }

        let nestedGroups = (groupsByParentID[group.id] ?? []).sorted { compareGroups($0, $1, by: criterion) }

        let startOffset = groupTabs.count + 1
        for (index, nestedGroup) in nestedGroups.enumerated() {
            nestedGroup.position = group.position + startOffset + index
            sortTabsInGroup(
                nestedGroup,
                by: criterion,
                tabsByGroupID: tabsByGroupID,
                groupsByParentID: groupsByParentID,
            )
        }
    }

    // MARK: - Comparison Helpers

    /// Compares two tabs by the given criterion.
    private func compareTabs(_ lhs: Tab, _ rhs: Tab, by criterion: TabSortCriterion) -> Bool {
        switch criterion {
        case .nameAscending:
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        case .nameDescending:
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedDescending
        case .domainAscending:
            let lhsDomain = lhs.activePage.url.host ?? ""
            let rhsDomain = rhs.activePage.url.host ?? ""
            return lhsDomain.localizedCaseInsensitiveCompare(rhsDomain) == .orderedAscending
        case .domainDescending:
            let lhsDomain = lhs.activePage.url.host ?? ""
            let rhsDomain = rhs.activePage.url.host ?? ""
            return lhsDomain.localizedCaseInsensitiveCompare(rhsDomain) == .orderedDescending
        case .recentFirst:
            // Never-accessed tabs sort last (oldest)
            switch (lhs.lastAccessed, rhs.lastAccessed) {
            case (nil, nil): return false
            case (nil, _): return false // lhs is "older"
            case (_, nil): return true // rhs is "older"
            case let (l?, r?): return l > r
            }
        case .oldestFirst:
            // Never-accessed tabs sort first (oldest)
            switch (lhs.lastAccessed, rhs.lastAccessed) {
            case (nil, nil): return false
            case (nil, _): return true // lhs is "older"
            case (_, nil): return false // rhs is "older"
            case let (l?, r?): return l < r
            }
        case .createdNewest:
            return lhs.createdAt > rhs.createdAt
        case .createdOldest:
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// Compares two groups by the given criterion.
    private func compareGroups(_ lhs: TabGroup, _ rhs: TabGroup, by criterion: TabSortCriterion) -> Bool {
        switch criterion {
        case .nameAscending, .domainAscending:
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .nameDescending, .domainDescending:
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
        case .recentFirst, .createdNewest:
            lhs.createdAt > rhs.createdAt
        case .oldestFirst, .createdOldest:
            lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Sort Key Helpers

    /// A unified sort key for comparing tabs and groups together.
    private enum SortKey {
        case string(String)
        case date(Date)
        case fallback
    }

    private func sortKeyForTab(_ tab: Tab, criterion: TabSortCriterion) -> SortKey {
        switch criterion {
        case .nameAscending, .nameDescending:
            .string(tab.displayTitle.lowercased())
        case .domainAscending, .domainDescending:
            .string((tab.activePage.url.host ?? "").lowercased())
        case .recentFirst, .oldestFirst:
            .date(tab.lastAccessed ?? .distantPast)
        case .createdNewest, .createdOldest:
            .date(tab.createdAt)
        }
    }

    private func sortKeyForGroup(_ group: TabGroup, criterion: TabSortCriterion) -> SortKey {
        switch criterion {
        case .nameAscending, .nameDescending, .domainAscending, .domainDescending:
            .string(group.name.lowercased())
        case .recentFirst, .oldestFirst, .createdNewest, .createdOldest:
            .date(group.createdAt)
        }
    }

    /// Compares two sort keys according to the criterion's direction.
    private func compareSortKeys(_ lhs: SortKey, _ rhs: SortKey, criterion: TabSortCriterion) -> Bool {
        switch (lhs, rhs) {
        case let (.string(lhsStr), .string(rhsStr)):
            let result = lhsStr.localizedCaseInsensitiveCompare(rhsStr)
            return criterion.isDescending ? result == .orderedDescending : result == .orderedAscending

        case let (.date(lhsDate), .date(rhsDate)):
            return criterion.isDescending ? lhsDate > rhsDate : lhsDate < rhsDate

        case (.fallback, _):
            return false

        case (_, .fallback):
            return true

        case (.string, .date), (.date, .string):
            return false
        }
    }
}
