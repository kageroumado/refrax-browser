import Foundation
import Observation

extension Sidebar {
    /// Manages multi-tab selection state for batch operations.
    ///
    /// Supports macOS-standard selection behavior:
    /// - **Command+Click**: Toggle individual tab selection
    /// - **Shift+Click**: Range selection from anchor to clicked tab
    /// - **Regular Click**: Clear selection and activate tab
    ///
    /// ## Selection Anchor
    ///
    /// The anchor is the starting point for Shift+Click range selection.
    /// It's set when:
    /// - User Command+Clicks a tab (that tab becomes anchor)
    /// - User activates a tab normally (active tab becomes anchor)
    ///
    /// ## Integration with Active Tab
    ///
    /// The currently active tab is always considered "selected" visually,
    /// but may not be in the `selectedTabIDs` set. Views should check both
    /// `isSelected(tab)` and `isActive(tab)` for proper highlighting.
    @Observable
    final class TabSelectionManager {
        // MARK: - Dependencies

        /// Layout manager for ordered item access.
        @ObservationIgnored
        unowned var layoutManager: Sidebar.LayoutManager!

        /// Window state for active tab reference.
        @ObservationIgnored
        unowned var windowState: WindowState!

        // MARK: - Selection State

        /// Set of currently selected tab IDs.
        ///
        /// Does not include the active tab unless explicitly selected.
        ///
        /// Marked `@ObservationIgnored` to prevent ForEach re-evaluation overhead.
        /// When selection changes, `selectionVersion` is incremented instead.
        /// Views should observe `selectionVersion` and then query `isSelected(_:)`.
        @ObservationIgnored
        private(set) var selectedTabIDs: Set<Tab.ID> = []

        /// Version counter incremented on every selection change.
        ///
        /// Views observe this to know when selection has changed, then call
        /// `isSelected(_:)` for specific tabs. This pattern avoids creating
        /// observation dependencies on the entire selectedTabIDs set, which
        /// would cause ForEach re-evaluation for ALL items on any change.
        private(set) var selectionVersion: UInt64 = 0

        /// Anchor tab ID for Shift+Click range selection.
        ///
        /// When user Shift+Clicks, all tabs between anchor and clicked tab
        /// are selected.
        private var anchorTabID: Tab.ID?

        // MARK: - Computed Properties

        /// Whether any tabs are currently selected (beyond the active tab).
        var hasSelection: Bool {
            !selectedTabIDs.isEmpty
        }

        /// Number of selected tabs.
        var selectionCount: Int {
            selectedTabIDs.count
        }

        /// All currently selected tabs in display order.
        ///
        /// Uses the layout manager's ordered items for consistent ordering.
        @ObservationIgnored
        var selectedTabs: [Tab] {
            let allItems = layoutManager.pinnedItems + layoutManager.normalItems
            return allItems.compactMap { item -> Tab? in
                guard let tab = item.tab, selectedTabIDs.contains(tab.id) else { return nil }
                return tab
            }
        }

        /// Selected tabs including the active tab if it's not already selected.
        ///
        /// Use this for operations that should include the active tab in batch actions.
        @ObservationIgnored
        var selectedTabsIncludingActive: [Tab] {
            var tabs = selectedTabs
            if let activeTab = windowState.activeTab,
               !selectedTabIDs.contains(activeTab.id) {
                tabs.insert(activeTab, at: 0)
            }
            return tabs
        }

        // MARK: - Selection Queries

        /// Whether a specific tab is in the selection set.
        ///
        /// - Parameter tab: The tab to check.
        /// - Returns: True if the tab is explicitly selected.
        func isSelected(_ tab: Tab) -> Bool {
            selectedTabIDs.contains(tab.id)
        }

        /// Whether a tab should show selection highlight.
        ///
        /// Returns true if the tab is either explicitly selected or is the active tab.
        ///
        /// - Parameter tab: The tab to check.
        /// - Returns: True if the tab should appear selected.
        func shouldHighlightAsSelected(_ tab: Tab) -> Bool {
            isSelected(tab) || windowState.activeTabID == tab.id
        }

        // MARK: - Selection Actions

        /// Handles a click on a tab with modifier keys.
        ///
        /// - Parameters:
        ///   - tab: The clicked tab.
        ///   - commandDown: Whether Command key is held.
        ///   - shiftDown: Whether Shift key is held.
        /// - Returns: Whether the tab should be activated (normal click behavior).
        func handleClick(on tab: Tab, commandDown: Bool, shiftDown: Bool) -> Bool {
            if commandDown {
                handleCommandClick(on: tab)
                return false
            } else if shiftDown {
                handleShiftClick(on: tab)
                return false
            } else {
                handleRegularClick(on: tab)
                return true
            }
        }

        /// Toggles selection for a single tab (Command+Click).
        ///
        /// - Parameter tab: The tab to toggle.
        private func handleCommandClick(on tab: Tab) {
            if selectedTabIDs.contains(tab.id) {
                selectedTabIDs.remove(tab.id)
                // If we deselected the anchor, clear it
                if anchorTabID == tab.id {
                    anchorTabID = selectedTabIDs.first
                }
            } else {
                selectedTabIDs.insert(tab.id)
                anchorTabID = tab.id
            }
            selectionVersion &+= 1
        }

        /// Selects a range of tabs from anchor to clicked tab (Shift+Click).
        ///
        /// - Parameter tab: The end of the range.
        private func handleShiftClick(on tab: Tab) {
            let allItems = layoutManager.pinnedItems + layoutManager.normalItems
            let tabIDs = allItems.compactMap(\.tab?.id)

            // Determine anchor: use explicit anchor, active tab, or clicked tab
            let effectiveAnchor = anchorTabID ?? windowState.activeTabID ?? tab.id

            guard let anchorIndex = tabIDs.firstIndex(of: effectiveAnchor),
                  let clickIndex = tabIDs.firstIndex(of: tab.id) else {
                // Fallback: just select the clicked tab
                selectedTabIDs.insert(tab.id)
                anchorTabID = tab.id
                selectionVersion &+= 1
                return
            }

            // Select all tabs in range
            let range = min(anchorIndex, clickIndex) ... max(anchorIndex, clickIndex)
            for index in range {
                selectedTabIDs.insert(tabIDs[index])
            }

            // Keep the original anchor (don't change it on shift-click)
            if anchorTabID == nil {
                anchorTabID = effectiveAnchor
            }
            selectionVersion &+= 1
        }

        /// Clears selection on regular click.
        ///
        /// - Parameter tab: The clicked tab (becomes new anchor).
        private func handleRegularClick(on tab: Tab) {
            clearSelection()
            anchorTabID = tab.id
        }

        /// Clears all selected tabs.
        func clearSelection() {
            guard !selectedTabIDs.isEmpty else { return }
            selectedTabIDs.removeAll()
            selectionVersion &+= 1
        }

        /// Updates anchor to the active tab.
        ///
        /// Called when tab is activated via normal means (not selection).
        func updateAnchorToActiveTab() {
            if let activeTabID = windowState.activeTabID {
                anchorTabID = activeTabID
            }
        }

        /// Removes a tab from selection if present.
        ///
        /// Used when a tab is closed or moved.
        ///
        /// - Parameter tabID: The ID of the tab to remove.
        func removeFromSelection(_ tabID: Tab.ID) {
            guard selectedTabIDs.remove(tabID) != nil else { return }
            if anchorTabID == tabID {
                anchorTabID = selectedTabIDs.first ?? windowState.activeTabID
            }
            selectionVersion &+= 1
        }

        /// Selects all tabs in the current space.
        func selectAll() {
            let allItems = layoutManager.pinnedItems + layoutManager.normalItems
            selectedTabIDs = Set(allItems.compactMap(\.tab?.id))
            anchorTabID = windowState.activeTabID ?? selectedTabIDs.first
            selectionVersion &+= 1
        }

        /// Inverts the current selection.
        func invertSelection() {
            let allItems = layoutManager.pinnedItems + layoutManager.normalItems
            let allTabIDs = Set(allItems.compactMap(\.tab?.id))
            selectedTabIDs = allTabIDs.subtracting(selectedTabIDs)
            selectionVersion &+= 1
        }
    }
}
