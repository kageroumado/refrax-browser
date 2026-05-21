import Foundation
import SwiftUI

// MARK: - Sidebar Types

/// Three collections in the sidebar
enum SidebarCollection: Equatable {
    case favorites
    case pinned
    case normal
}

/// Represents an item in the tab list - either a tab or a group
///
/// This enum allows the tab list to display a mixed collection of tabs and groups
/// in a single unified list, simplifying the rendering logic and enabling
/// position-based ordering of all items together.
enum TabListItem: Identifiable, Equatable {
    case tab(Tab)
    case group(TabGroup)
    
    var id: UUID {
        switch self {
        case let .tab(tab): tab.id
        case let .group(group): group.id
        }
    }
    
    var isPinned: Bool {
        switch self {
        case let .tab(tab): tab.isPinned
        case let .group(group): group.isPinned
        }
    }
    
    var position: Int {
        switch self {
        case let .tab(tab): tab.position
        case let .group(group): group.position
        }
    }
    
    var tab: Tab? {
        if case let .tab(tab) = self { return tab }
        return nil
    }
    
    var group: TabGroup? {
        if case let .group(group) = self { return group }
        return nil
    }
    
    static func == (lhs: TabListItem, rhs: TabListItem) -> Bool {
        lhs.id == rhs.id
    }

    var debugName: String {
        switch self {
        case let .tab(tab): "tab:\(tab.displayTitle.prefix(15))"
        case let .group(group): "grp:\(group.name)"
        }
    }
}
