import Foundation

// MARK: - Multi-Window Ownership

extension WebPage {
    /// Claims ownership of the interactive WebView for a specific window.
    ///
    /// Call this when a window becomes key while displaying this page.
    ///
    /// - Parameter windowState: The window state claiming ownership.
    func claimOwnership(for windowState: WindowState) {
        ownerWindowID = ObjectIdentifier(windowState)
    }

    /// Claims ownership using a raw identifier.
    ///
    /// Used by reflected windows which don't have a full WindowState.
    ///
    /// - Parameter id: The identifier claiming ownership.
    func claimOwnership(id: ObjectIdentifier) {
        ownerWindowID = id
    }

    /// Checks if the given window is the current owner of the interactive WebView.
    ///
    /// - Parameter windowState: The window state to check.
    /// - Returns: `true` if the window is the owner, `false` otherwise.
    func isOwner(_ windowState: WindowState) -> Bool {
        ownerWindowID == ObjectIdentifier(windowState)
    }

    /// Checks ownership using a raw identifier.
    ///
    /// - Parameter id: The identifier to check.
    /// - Returns: `true` if the identifier is the owner, `false` otherwise.
    func isOwner(id: ObjectIdentifier) -> Bool {
        ownerWindowID == id
    }

    /// Releases ownership if the given window is the current owner.
    ///
    /// - Parameter windowState: The window state releasing ownership.
    func releaseOwnership(for windowState: WindowState) {
        if isOwner(windowState) {
            ownerWindowID = nil
        }
    }

    /// Releases ownership using a raw identifier.
    ///
    /// - Parameter id: The identifier releasing ownership.
    func releaseOwnership(id: ObjectIdentifier) {
        if isOwner(id: id) {
            ownerWindowID = nil
        }
    }
}

// MARK: - Reflected Windows

extension WebPage {
    /// Creates a new reflected window for this page.
    ///
    /// Reflected windows use the owner/portal mechanism for displaying web content.
    /// When the reflected window becomes key, it claims ownership of the interactive
    /// WebView, and other windows automatically switch to portal mode.
    ///
    /// - Parameter environment: The Refrax environment for SwiftUI injection.
    /// - Returns: The created reflected window controller.
    @discardableResult
    func createReflectedWindow(environment: RefraxEnvironment) -> ReflectedViewController {
        let controller = ReflectedViewController(webPage: self, environment: environment)
        _reflectedWindows.append(controller)
        reflectedWindowCount = _reflectedWindows.count
        return controller
    }

    /// Brings all reflected windows to the front.
    func bringReflectedWindowsToFront() {
        for controller in _reflectedWindows {
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Closes all reflected windows.
    func closeAllReflectedWindows() {
        // Copy array since close() modifies _reflectedWindows
        let controllers = _reflectedWindows
        for controller in controllers {
            controller.window?.close()
        }
    }

    /// Called when a reflected window closes itself.
    ///
    /// - Parameter controller: The reflected window controller that closed.
    func reflectedWindowDidClose(_ controller: ReflectedViewController) {
        _reflectedWindows.removeAll { $0 === controller }
        reflectedWindowCount = _reflectedWindows.count
    }
}
