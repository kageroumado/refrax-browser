import Foundation

// MARK: - A Tab in Its Own Window

extension TabManager {
    /// Whether `tab` is the page of a browser window other than `windowState`'s. Such a tab is
    /// shown in that window and nowhere else, so this window's floating layer leaves it out.
    func isShownInAnotherWindow(_ tab: Tab, besides windowState: WindowState) -> Bool {
        windowManager.allWindowStates.contains { $0 !== windowState && $0.activeTabID == tab.id }
    }

    /// Moves `tab` out of `windowState` into a new window of the same space, where it is the
    /// page. The window it leaves shows the tab it showed before, or the most recent other one.
    @discardableResult
    func moveTabToNewWindow(_ tab: Tab, from windowState: WindowState) -> RefraxWindowController? {
        guard !tab.isArchived, !tab.isFavorite, let space = tab.space else { return nil }
        // The new window shows the tab first, so the window it leaves sees it shown elsewhere
        // and does not hand it to its floating layer.
        let controller = windowManager.createWindow(with: space, activating: tab)
        if windowState.activeTabID == tab.id {
            if let replacement = replacementTab(for: tab, in: space, windowState: windowState) {
                setActiveTab(replacement, in: windowState)
            } else {
                windowState.setActiveTabID(nil, for: space.id, trackPrevious: false)
            }
        }
        return controller
    }

    /// The page a window shows after its page leaves: the one it showed before, else the most
    /// recently used page of the space that no other window shows.
    private func replacementTab(for tab: Tab, in space: Space, windowState: WindowState) -> Tab? {
        let candidates = space.mainTabs.filter { $0.id != tab.id && !$0.isArchived && !isShownInAnotherWindow($0, besides: windowState) }
        if let previousID = windowState.previousActiveTabID(for: space.id), let previous = candidates.first(where: { $0.id == previousID }) {
            return previous
        }
        return candidates.max { ($0.lastAccessed ?? .distantPast) < ($1.lastAccessed ?? .distantPast) }
    }
}

// MARK: - Unlocking Before a Move

extension TabManager {
    /// Unlocks every locked space in `spaces`, one prompt each, and reports whether all of
    /// them are now open. A canceled or failed prompt stops at that space.
    func unlock(_ spaces: [Space]) async -> Bool {
        var seen: Set<Space.ID> = []
        for space in spaces where seen.insert(space.id).inserted && state.spaceLockManager.requiresAuth(for: space) {
            guard await state.spaceLockManager.authenticate(for: space) == .success else { return false }
        }
        return true
    }

    /// Moves `tabs` to `space` after unlocking the spaces they leave and the one they enter;
    /// a lock left closed moves nothing. See ``moveTabs(_:to:confirmingIn:)``.
    func moveTabsUnlocking(_ tabs: [Tab], to space: Space, confirmingIn windowState: WindowState) async {
        guard await unlock([space] + tabs.compactMap(\.space)) else { return }
        moveTabs(tabs, to: space, confirmingIn: windowState)
    }

    /// Moves `tabs` to `space` as an undoable action, and confirms it with a toast in
    /// `windowState` whose Undo button puts them back.
    func moveTabs(_ tabs: [Tab], to space: Space, confirmingIn windowState: WindowState) {
        let origins = tabs.compactMap(UndoRedoManager.TabSpaceOrigin.init)
        guard !origins.isEmpty else { return }
        moveTabs(tabs, to: space)
        let actionName = "Move to \(space.name)"
        undoRedoManager.registerMoveToSpace(origins, actionName: actionName)
        let undo = undoRedoManager
        windowState.showToast("Moved to \(space.name)", action: ToastAction(title: "Undo") {
            _ = undo?.undoMoveToSpace(named: actionName)
        })
    }
}

// MARK: - Clearing a Space

extension TabManager {
    /// Closes every tab and group in `space` and gives it the default name, icon, and color.
    /// This is how the last space is emptied, since a browser always keeps one.
    func clearSpace(_ space: Space) {
        for tab in state.tabs(in: space) {
            closeTab(tab)
        }
        for group in state.groups(in: space) {
            groupManager.deleteGroup(group, in: space, deleteContainedTabs: false)
        }
        spaceManager.updateSpace(
            space,
            name: SpaceManager.DefaultSpaceConfig.name,
            iconName: SpaceManager.DefaultSpaceConfig.iconName,
            color: SpaceManager.DefaultSpaceConfig.color,
        )
    }
}
