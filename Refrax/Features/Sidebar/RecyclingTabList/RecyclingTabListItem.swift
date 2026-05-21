import Foundation

/// A single row in the recycling tab list's flat item array.
///
/// The recycling list flattens the sidebar's logical sections (pinned, new-tab button,
/// normal) into a single contiguous array. Each item maps to one row at uniform height.
///
/// For the compact sidebar, group headers and group children are also flat rows —
/// group backgrounds are rendered as separate CALayers, not as wrapping containers.
enum RecyclingTabListItem: Identifiable {
    /// A tab or group header from the layout manager.
    case sidebarItem(TabListItem, collection: SidebarCollection)

    /// The new-tab / command-lens button between pinned and normal sections.
    case newTabButton

    /// Section divider (compact sidebar only).
    case compactDivider

    /// Command lens button (compact sidebar only).
    case compactCommandLens

    // Stable IDs for non-tab rows
    private static let newTabButtonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let compactDividerID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let compactCommandLensID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    var id: UUID {
        switch self {
        case .sidebarItem(let item, _):
            return item.id
        case .newTabButton:
            return Self.newTabButtonID
        case .compactDivider:
            return Self.compactDividerID
        case .compactCommandLens:
            return Self.compactCommandLensID
        }
    }

    /// Build the flat item array for the full sidebar.
    static func buildFullSidebarItems(
        pinnedItems: [TabListItem],
        normalItems: [TabListItem],
    ) -> [RecyclingTabListItem] {
        var result: [RecyclingTabListItem] = []
        result.reserveCapacity(pinnedItems.count + 1 + normalItems.count)

        for item in pinnedItems {
            result.append(.sidebarItem(item, collection: .pinned))
        }
        result.append(.newTabButton)
        for item in normalItems {
            result.append(.sidebarItem(item, collection: .normal))
        }
        return result
    }

}

extension RecyclingTabListItem: Hashable {
    static func == (lhs: RecyclingTabListItem, rhs: RecyclingTabListItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension RecyclingTabListItem {
    /// Build the flat item array for the compact sidebar.
    static func buildCompactSidebarItems(
        pinnedItems: [TabListItem],
        normalItems: [TabListItem],
    ) -> [RecyclingTabListItem] {
        var result: [RecyclingTabListItem] = []
        result.reserveCapacity(pinnedItems.count + 2 + normalItems.count)

        for item in pinnedItems {
            result.append(.sidebarItem(item, collection: .pinned))
        }
        if !pinnedItems.isEmpty {
            result.append(.compactDivider)
        }
        result.append(.compactCommandLens)
        for item in normalItems {
            result.append(.sidebarItem(item, collection: .normal))
        }
        return result
    }
}
