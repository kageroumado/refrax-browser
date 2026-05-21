import AppKit
import Foundation
import Observation
import SwiftUI

/// Centralized manager for all browser-level undo/redo operations.
///
/// `UndoRedoManager` provides a single, global `UndoManager` for browser actions
/// like closing tabs, deleting groups, and other reversible operations. This ensures
/// consistent undo/redo behavior across all windows, similar to Safari.
///
/// ## Architecture
///
/// The manager owns a single `UndoManager` instance that is used for all browser-level
/// actions. This is intentionally separate from WebView's internal undo management
/// (which handles text editing within pages).
///
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │ UndoRedoManager (app-global singleton)                  │
/// │   undoManager: UndoManager  ← for browser actions       │
/// │   recentlyClosedTabs: [ClosedTabInfo]                   │
/// │   recentlyDeletedGroups: [ClosedGroupInfo]              │
/// └─────────────────────────────────────────────────────────┘
/// ```
///
/// ## Why Separate from Standard Undo?
///
/// WebKit's `WKWebView` (and its internal `WKContentView`) claims ownership of the
/// `undo:` and `redo:` selectors through `validateUserInterfaceItem:`. Even when
/// the web page has nothing to undo, WebKit validates YES for these actions because
/// it maintains an editable context. This prevents the standard responder chain from
/// reaching our window controller for browser-level undo operations.
///
/// To work around this, we:
/// 1. Keep standard `undo:`/`redo:` menu items for WebKit text editing
/// 2. Add separate "Undo Close Tab"/"Redo Close Tab" menu items for browser actions
/// 3. Use a keyboard event monitor in `RefraxWindowController` to intercept Cmd+Z
///    when WebKit has nothing to undo, falling back to browser-level undo
///
/// ## Safari-Like Behavior
///
/// - Cmd+Z after closing a tab restores that tab (via event monitor)
/// - "Undo Close Tab" menu item shows the specific action name
/// - "Reopen Last Closed Tab" (Cmd+Shift+T) reopens and removes from list
/// - "Recently Closed" submenu shows last 10 closed tabs
/// - Undo/Redo is global across all windows
///
/// ## Usage
///
/// ```swift
/// // Register a tab close (called by TabManager)
/// undoRedoManager.registerCloseTab(closedInfo)
///
/// // Reopen last closed tab (Cmd+Shift+T)
/// undoRedoManager.reopenLastClosedTab()
///
/// // Access for menu/UI
/// let closedTabs = undoRedoManager.recentlyClosedTabs
/// ```
@Observable
final class UndoRedoManager {
    // MARK: - Properties

    /// Global UndoManager for browser-level actions.
    ///
    /// This is NOT per-window - undo/redo applies across all windows.
    /// WebView text editing uses its own internal UndoManager.
    let undoManager = UndoManager()

    /// Recently closed tabs available for reopening.
    ///
    /// Ordered by close time (most recent first). Limited to `maxRecentlyClosedTabs`.
    /// Includes both main tabs and reference tabs.
    private(set) var recentlyClosedTabs: [ClosedTabInfo] = []

    /// Recently deleted groups available for restoration.
    ///
    /// Ordered by deletion time (most recent first). Limited to `maxRecentlyDeletedGroups`.
    private(set) var recentlyDeletedGroups: [ClosedGroupInfo] = []

    // MARK: - Configuration

    /// Maximum number of recently closed tabs to track.
    let maxRecentlyClosedTabs = 10

    /// Maximum number of recently deleted groups to track.
    let maxRecentlyDeletedGroups = 10

    // MARK: - Dependencies

    /// Reference to TabManager for restore operations.
    ///
    /// Set after initialization to avoid circular dependency.
    unowned var tabManager: TabManager!

    /// Reference to TabGroupManager for group restore operations.
    ///
    /// Set after initialization to avoid circular dependency.
    unowned var tabGroupManager: TabGroupManager!

    /// Reference to SpaceManager for space restore operations.
    ///
    /// Set after initialization to avoid circular dependency.
    unowned var spaceManager: SpaceManager!

    /// Recently converted spaces (for potential undo).
    private(set) var recentSpaceToGroupConversions: [ConvertedSpaceInfo] = []

    /// Recently converted groups (for potential undo).
    private(set) var recentGroupToSpaceConversions: [ConvertedGroupToSpaceInfo] = []

    /// Maximum number of conversions to track.
    let maxConversions = 10

    // MARK: - Menu Integration

    /// The title for the browser-level undo menu item.
    ///
    /// Returns "Undo [action name]" if undo is available, otherwise "Undo".
    /// Used by MenuBarManager to show specific action names in the Edit menu.
    var undoMenuTitle: String {
        guard undoManager.canUndo else { return "Undo" }
        let actionName = undoManager.undoActionName
        if !actionName.isEmpty {
            return "Undo \(actionName)"
        }
        return "Undo"
    }

    /// The title for the browser-level redo menu item.
    ///
    /// Returns "Redo [action name]" if redo is available, otherwise "Redo".
    var redoMenuTitle: String {
        guard undoManager.canRedo else { return "Redo" }
        let actionName = undoManager.redoActionName
        if !actionName.isEmpty {
            return "Redo \(actionName)"
        }
        return "Redo"
    }

    // MARK: - Initialization

    init() {
        // UndoManager setup
        undoManager.levelsOfUndo = 50
    }

    // MARK: - Tab Undo Operations

    /// Registers a tab close for undo and adds to recently closed list.
    ///
    /// This is called by TabManager when closing a tab. It:
    /// 1. Adds the tab info to `recentlyClosedTabs`
    /// 2. Registers an undo action to restore the tab
    ///
    /// When the user presses Cmd+Z, the tab is restored and removed from
    /// the recently closed list.
    ///
    /// - Parameter info: Information about the closed tab.
    func registerCloseTab(_ info: ClosedTabInfo) {
        addToRecentlyClosed(info)

        let title = info.title
        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            restoreTabFromUndo(info)
        }
        undoManager.setActionName("Close Tab \"\(title)\"")
    }

    /// Registers a batch of tab closes for undo.
    ///
    /// Used for operations like "Close Other Tabs", "Close Tabs Below", etc.
    /// All tabs are restored together in a single undo operation.
    ///
    /// - Parameters:
    ///   - infos: Information about the closed tabs.
    ///   - actionName: Name shown in Edit menu (e.g., "Close 5 Tabs").
    func registerCloseTabsBatch(_ infos: [ClosedTabInfo], actionName: String) {
        guard !infos.isEmpty else { return }

        for info in infos {
            addToRecentlyClosed(info)
        }

        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            // Restore in reverse order to maintain original positions
            for info in infos.reversed() {
                restoreTabFromUndo(info)
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Registers a reference tab close for undo.
    ///
    /// Reference tabs are tracked separately but use the same undo system.
    ///
    /// - Parameter info: Information about the closed reference tab.
    func registerCloseReferenceTab(_ info: ClosedTabInfo) {
        addToRecentlyClosed(info)

        let title = info.title
        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            restoreReferenceTabFromUndo(info)
        }
        undoManager.setActionName("Close Reference Tab \"\(title)\"")
    }

    // MARK: - Group Undo Operations

    /// Registers a group deletion for undo.
    ///
    /// When undone, restores the group and all its tabs.
    ///
    /// - Parameter info: Information about the deleted group.
    func registerDeleteGroup(_ info: ClosedGroupInfo) {
        addToRecentlyDeleted(info)

        let name = info.name
        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            restoreGroupFromUndo(info)
        }
        undoManager.setActionName("Delete Group \"\(name)\"")
    }

    // MARK: - Reopen Actions

    /// Reopens the most recently closed tab.
    ///
    /// This is the action for Cmd+Shift+T. Unlike undo, this specifically
    /// targets the most recently closed tab regardless of other undo actions.
    ///
    /// The tab is removed from `recentlyClosedTabs` after reopening.
    func reopenLastClosedTab() {
        guard let info = recentlyClosedTabs.first else { return }

        if info.isReferenceTab {
            tabManager.restoreReferenceTab(info)
        } else {
            tabManager.restoreTab(info)
        }
        recentlyClosedTabs.removeFirst()

        Logger.info("Reopened last closed tab: \(info.title)", category: Logger.tabs)
    }

    /// Reopens a specific recently closed tab by index.
    ///
    /// Used by the "Recently Closed" submenu in the History menu.
    ///
    /// - Parameter index: Index in the `recentlyClosedTabs` array.
    func reopenClosedTab(at index: Int) {
        guard index >= 0, index < recentlyClosedTabs.count else { return }

        let info = recentlyClosedTabs.remove(at: index)

        if info.isReferenceTab {
            tabManager.restoreReferenceTab(info)
        } else {
            tabManager.restoreTab(info)
        }

        Logger.info("Reopened closed tab at index \(index): \(info.title)", category: Logger.tabs)
    }

    /// Clears all recently closed tabs.
    ///
    /// Used when clearing browser history.
    func clearRecentlyClosedTabs() {
        recentlyClosedTabs.removeAll()
        Logger.info("Cleared recently closed tabs", category: Logger.tabs)
    }

    // MARK: - Private Helpers

    /// Adds a closed tab info to the recently closed list.
    private func addToRecentlyClosed(_ info: ClosedTabInfo) {
        recentlyClosedTabs.insert(info, at: 0)
        if recentlyClosedTabs.count > maxRecentlyClosedTabs {
            recentlyClosedTabs.removeLast()
        }
    }

    /// Adds a deleted group info to the recently deleted list.
    private func addToRecentlyDeleted(_ info: ClosedGroupInfo) {
        recentlyDeletedGroups.insert(info, at: 0)
        if recentlyDeletedGroups.count > maxRecentlyDeletedGroups {
            recentlyDeletedGroups.removeLast()
        }
    }

    /// Restores a tab from an undo action.
    ///
    /// This is called when the user presses Cmd+Z after closing a tab.
    /// It restores the tab and removes it from the recently closed list.
    private func restoreTabFromUndo(_ info: ClosedTabInfo) {
        tabManager.restoreTab(info)
        recentlyClosedTabs.removeAll { $0.id == info.id }
    }

    /// Restores a reference tab from an undo action.
    private func restoreReferenceTabFromUndo(_ info: ClosedTabInfo) {
        tabManager.restoreReferenceTab(info)
        recentlyClosedTabs.removeAll { $0.id == info.id }
    }

    /// Restores a group from an undo action.
    private func restoreGroupFromUndo(_ info: ClosedGroupInfo) {
        tabGroupManager.restoreGroup(info)
        recentlyDeletedGroups.removeAll { $0.id == info.id }
    }

    // MARK: - Conversion Undo Operations

    /// Registers a space-to-group conversion for undo.
    ///
    /// - Parameters:
    ///   - info: Captured state of the original space.
    ///   - resultGroupID: The ID of the created group.
    func registerSpaceToGroupConversion(_ info: ConvertedSpaceInfo, resultGroupID: UUID) {
        var updatedInfo = info
        updatedInfo.resultGroupID = resultGroupID

        recentSpaceToGroupConversions.insert(updatedInfo, at: 0)
        if recentSpaceToGroupConversions.count > maxConversions {
            recentSpaceToGroupConversions.removeLast()
        }

        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            undoSpaceToGroupConversion(updatedInfo)
        }
        undoManager.setActionName("Convert \"\(info.spaceName)\" to Group")
    }

    /// Registers a group-to-space conversion for undo.
    ///
    /// - Parameters:
    ///   - info: Captured state of the original group.
    ///   - resultSpaceID: The ID of the created space.
    func registerGroupToSpaceConversion(_ info: ConvertedGroupToSpaceInfo, resultSpaceID: UUID) {
        var updatedInfo = info
        updatedInfo.resultSpaceID = resultSpaceID

        recentGroupToSpaceConversions.insert(updatedInfo, at: 0)
        if recentGroupToSpaceConversions.count > maxConversions {
            recentGroupToSpaceConversions.removeLast()
        }

        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            undoGroupToSpaceConversion(updatedInfo)
        }
        undoManager.setActionName("Convert \"\(info.groupName)\" to Space")
    }

    /// Undoes a space-to-group conversion by restoring the original space.
    private func undoSpaceToGroupConversion(_ info: ConvertedSpaceInfo) {
        guard let resultGroupID = info.resultGroupID else {
            Logger.warning("Cannot undo space-to-group conversion: result group ID missing", category: Logger.tabs)
            return
        }

        // Find the group created by the conversion
        let allGroups = tabGroupManager.groups()
        guard let group = allGroups.first(where: { $0.id == resultGroupID }),
              let targetSpace = group.space
        else {
            Logger.warning("Cannot undo space-to-group conversion: result group not found", category: Logger.tabs)
            return
        }

        // Recreate the original space
        let restoredSpace = spaceManager.createSpace(
            name: info.spaceName,
            color: info.spaceColor,
            iconName: info.spaceIconName,
            dataStoreMode: info.dataStoreMode,
        )

        // Move tabs back to the restored space
        let tabsToMove = group.tabs.sorted { $0.position < $1.position }
        for (index, tab) in tabsToMove.enumerated() {
            tab.space = restoredSpace
            tab.groupID = nil
            tab.group = nil
            tab.position = index
        }

        // Restore reference tabs
        for tabInfo in info.referenceTabInfos {
            if let tab = tabManager.state.tab(for: tabInfo.tabID) {
                tab.space = restoredSpace
                tab.isReferenceTab = true
                tab.position = tabInfo.position
            }
        }

        // Delete the result group
        tabGroupManager.deleteGroup(group, in: targetSpace, deleteContainedTabs: false)

        recentSpaceToGroupConversions.removeAll { $0.originalSpaceID == info.originalSpaceID }

        Logger.info("Undid space-to-group conversion: restored '\(info.spaceName)'", category: Logger.tabs)
    }

    /// Undoes a group-to-space conversion by restoring the original group.
    private func undoGroupToSpaceConversion(_ info: ConvertedGroupToSpaceInfo) {
        guard let resultSpaceID = info.resultSpaceID else {
            Logger.warning("Cannot undo group-to-space conversion: result space ID missing", category: Logger.tabs)
            return
        }

        // Find the spaces
        let spaces = spaceManager.spaces
        guard let resultSpace = spaces.first(where: { $0.id == resultSpaceID }),
              let sourceSpace = spaces.first(where: { $0.id == info.sourceSpaceID })
        else {
            Logger.warning("Cannot undo group-to-space conversion: spaces not found", category: Logger.tabs)
            return
        }

        do {
            // Recreate the original group
            let group = try tabGroupManager.createGroup(
                in: sourceSpace,
                name: info.groupName,
                color: info.groupColorHex,
                iconName: info.groupIconName,
            )
            group.isPinned = info.isPinned
            group.isCollapsed = info.isCollapsed

            // Move tabs back to the restored group
            for tab in resultSpace.tabs {
                tab.space = sourceSpace
                tab.groupID = group.id
                tab.group = group
            }

            // Delete the result space
            spaceManager.deleteSpace(resultSpace, windowState: nil)

            recentGroupToSpaceConversions.removeAll { $0.originalGroupID == info.originalGroupID }

            Logger.info("Undid group-to-space conversion: restored group '\(info.groupName)'", category: Logger.tabs)
        } catch {
            Logger.warning("Failed to undo group-to-space conversion: \(error)", category: Logger.tabs)
        }
    }
}

// MARK: - Conversion Info Types

/// Captured state for undoing a space-to-group conversion.
struct ConvertedSpaceInfo: Equatable {
    let originalSpaceID: UUID
    let spaceName: String
    let spaceIconName: String
    let spaceColor: Color
    let dataStoreMode: DataStoreMode
    let position: Int
    let tabInfos: [ConvertedTabInfo]
    let referenceTabInfos: [ConvertedTabInfo]
    let targetSpaceID: UUID
    var resultGroupID: UUID?
}

/// Captured state for undoing a group-to-space conversion.
struct ConvertedGroupToSpaceInfo: Equatable {
    let originalGroupID: UUID
    let groupName: String
    let groupColorHex: String
    let groupIconName: String?
    let position: Int
    let isPinned: Bool
    let isCollapsed: Bool
    let sourceSpaceID: UUID
    let tabInfos: [ConvertedTabInfo]
    var resultSpaceID: UUID?
}

/// Captured tab info for conversion undo.
struct ConvertedTabInfo: Equatable {
    let tabID: UUID
    let position: Int
    let groupID: UUID?
    let isPinned: Bool
    let isReferenceTab: Bool
}
