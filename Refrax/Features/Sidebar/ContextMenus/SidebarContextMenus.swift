import AppKit
import SwiftUI

// MARK: - Sidebar Context Menus

/// Unified context menu definitions for all sidebar items.
///
/// This file consolidates all sidebar context menus in one place for easier
/// maintenance and consistent behavior. Each entity type (tab, group, favorite)
/// has its own menu content that composes shared building blocks.
///
/// ## Architecture
///
/// - **Building blocks**: Reusable menu sections (group picker, space picker, etc.)
/// - **Entity menus**: Compose building blocks for specific item types
/// - **Shared environment**: All menus access TabManager and WindowState
///
/// ## Usage
///
/// ```swift
/// .contextMenu {
///     SidebarContextMenus.Tab(tab: tab, onRename: { ... })
/// }
/// ```
///
/// ## File Organization
///
/// The context menu implementations are split across multiple files:
/// - `SidebarContextMenus.swift` - Container enum and Environment
/// - `TabContextMenus.swift` - Tab, ArchivedTab, MultiTab menus
/// - `OrganizationContextMenus.swift` - Group, SpaceMenu menus
/// - `BookmarkContextMenus.swift` - Favorite, FolderFavorite menus
/// - `SidebarMenuBuilders.swift` - Empty area menu, sort menu, AppKit builders
enum SidebarContextMenus {
    // MARK: - Environment Container

    /// Provides shared environment access for all context menu content.
    ///
    /// Context menu views can't directly use @Environment, so we pass
    /// the managers as parameters from the parent view.
    struct Environment {
        let tabManager: TabManager
        let windowState: WindowState
        let bookmarksManager: BookmarksManager?

        var activeSpace: Space? { windowState.activeSpace }
        var availableSpaces: [Space] {
            tabManager.state.spaces.filter { $0.id != windowState.activeSpaceID }
        }

        var availableGroups: [TabGroup] {
            activeSpace?.groups ?? []
        }

        /// Groups that can be nested into (root-level groups only).
        func nestableGroups(excluding groupID: UUID) -> [TabGroup] {
            activeSpace?.groups.filter {
                $0.id != groupID && $0.parentGroupID == nil && !$0.isArchive
            } ?? []
        }
    }
}
