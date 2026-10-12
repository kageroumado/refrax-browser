import Foundation

extension TabManager {
    /// Opens a reference while retaining the window's original activity.
    func look(at tab: Tab, in window: WindowState) {
        guard !tab.isArchived, tab.id != window.activeTabID else { return }
        if let space = tab.space, state.spaceLockManager.requiresAuth(for: space) {
            let startingID = window.activeTabID
            window.pageVisit.authenticationTask?.cancel()
            window.pageVisit.authenticationTask = Task.immediate(name: "Unlock reference for Look") { [weak self, weak window] in
                guard let self, let window else { return }
                let result = await state.spaceLockManager.authenticate(for: space)
                guard case .success = result, !Task.isCancelled, window.activeTabID == startingID else { return }
                look(at: tab, in: window)
            }
            return
        }
        if let source = window.activeTab {
            window.pageVisit.begin(from: source, in: window, page: pagePool.existingPage(for: source.activePage))
        }
        window.controlIsland.holdAwake(for: ControlIslandState.visitHold)
        if let space = tab.space, space.id != window.activeSpaceID { spaceManager.switchToSpaceSync(space, for: window) }
        setActiveTab(tab, in: window, preservingVisit: true)
    }

    func look(at url: URL, in window: WindowState) {
        guard let space = window.activeSpace else { return }
        let tab = createTab(url: url, in: space, makeActive: false)
        look(at: tab, in: window)
    }

    @discardableResult
    func returnFromLook(in window: WindowState) -> Bool {
        guard let destination = window.pageVisit.destination,
              let tab = state.tab(for: destination.tabID), !tab.isArchived else {
            window.pageVisit.end()
            return false
        }
        if let space = tab.space ?? state.spaces.first(where: { $0.id == destination.spaceID }), space.id != window.activeSpaceID {
            if state.spaceLockManager.requiresAuth(for: space) {
                window.pageVisit.authenticationTask?.cancel()
                window.pageVisit.authenticationTask = Task.immediate(name: "Unlock return destination") { [weak self, weak window] in
                    guard let self, let window else { return }
                    let result = await state.spaceLockManager.authenticate(for: space)
                    guard case .success = result, !Task.isCancelled, window.pageVisit.destination == destination else { return }
                    returnFromLook(in: window)
                }
                return false
            }
            spaceManager.switchToSpaceSync(space, for: window)
        }
        setActiveTab(tab, in: window, preservingVisit: true)
        window.pageVisit.restoreFocus(in: window)
        window.pageVisit.end()
        return true
    }
}
