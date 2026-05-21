import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Helper Types

    struct ValidatedItem {
        let item: TabListItem
        let frame: CGRect
        let metadata: Sidebar.LayoutManager.ItemMetadata
    }

    /// Overlay appearance mode during drag.
    ///
    /// The overlay morphs between modes when crossing zone boundaries:
    /// - `.tabRow`: Standard horizontal tab appearance (~300x36)
    /// - `.tile`: Grid tile appearance (specified size, typically ~80x80)
    enum OverlayMode: Equatable {
        /// Standard tab row appearance (horizontal layout with favicon + title)
        case tabRow
        /// Grid tile appearance at specified size
        case tile(CGSize)

        /// Target frame size for this mode
        var targetSize: CGSize {
            switch self {
            case .tabRow:
                CGSize(width: 300, height: Constants.Layout.tabItemHeight)
            case let .tile(size):
                size
            }
        }
    }

    enum DraggedItem {
        case favorite(FavoriteItem)
        case tab(Tab)
        case group(TabGroup)

        var id: UUID {
            switch self {
            case let .favorite(item): item.id
            case let .tab(tab): tab.id
            case let .group(group): group.id
            }
        }

        var favorite: FavoriteItem? {
            if case let .favorite(item) = self { return item }
            return nil
        }

        var tab: Tab? {
            if case let .tab(tab) = self { return tab }
            return nil
        }

        var group: TabGroup? {
            if case let .group(group) = self { return group }
            return nil
        }

        var isPinned: Bool {
            switch self {
            case .favorite:
                true
            case let .tab(tab):
                tab.isPinned
            case let .group(tabGroup):
                tabGroup.isPinned == true
            }
        }

        var displayName: String {
            switch self {
            case let .favorite(item): item.displayName
            case let .tab(tab): tab.displayTitle
            case let .group(group): group.name
            }
        }
    }

    enum DropTarget: Equatable {
        case none
        case reorder(target: ItemPosition)
        case convertToFavorite(mode: FavoriteMode)
        case convertToTab(targetSpace: Space, targetPosition: ItemPosition)
        case addToGroup(groupID: UUID)
        case nestGroup(parentGroupID: UUID)
    }

    /// Active drop zone for visual feedback
    enum DropZone: Equatable {
        case favoritesGrid
        case pinnedSection
        case normalSection
        case groupHeader(UUID)
    }
}
