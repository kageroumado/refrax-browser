import Foundation
import SwiftData

// MARK: - Favorites to Tabs

extension TabManager {
    /// Converts a favorite to a regular tab in the active space.
    ///
    /// Used when removing a favorite from Favorites: instead of closing the tab, it becomes
    /// a regular tab at the top of the tab list. The bookmark/tab link is broken.
    ///
    /// - Parameters:
    ///   - tab: The live favorite tab to convert.
    ///   - bookmark: The associated bookmark (will have its link cleared).
    ///   - targetWindow: The window that receives the tab. Defaults to the active window.
    /// - Returns: `true` if successful, `false` if no active window/space.
    @discardableResult
    func convertLiveFavoriteToTab(_ tab: Tab, bookmark: Bookmark, in targetWindow: WindowState? = nil) -> Bool {
        guard let windowState = targetWindow ?? activeWindowState,
              let activeSpace = windowState.activeSpace else {
            return false
        }

        // Check if this was the active tab BEFORE we modify state
        let wasActiveLiveFavorite = windowState.activeTab == tab

        // Prepend to the tabs outside pinned groups
        let firstPosition = activeSpace.unpinnedTabs.first?.position ?? 1_000_000
        tab.position = firstPosition - 1

        state.convertFavoriteToSpaceTab(tab, in: activeSpace)

        // Break the live favorite link
        bookmark.linkedTab = nil
        tab.linkedBookmark = nil

        // If this was the active live favorite, keep it active (now as a space tab)
        if wasActiveLiveFavorite {
            setActiveTab(tab, in: windowState)
        }

        scheduleSave()
        return true
    }
}
