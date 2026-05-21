import AppKit
import Combine
import SwiftUI

/// Controller for the detached reference pane window.
///
/// Hosts `ReferencePaneWindowContentView` in a separate window that shares state
/// with the parent browser window. The reference pane window has a compact
/// toolbar with navigation controls and address display.
///
/// ## Architecture
///
/// The controller observes the parent `WindowState` for space changes.
/// When the active space changes, the view automatically updates to show
/// the new space's reference tabs or empty state.
///
/// ## Toolbar Layout
///
/// Uses a compact toolbar style with centered controls:
/// ```
/// [Close][Min][Max]     [Address] [Tabs▼] [Dock]
/// ```
final class ReferencePaneWindowController: NSWindowController, NSWindowDelegate {
    private let parentWindowState: WindowState
    private let environment: RefraxEnvironment
    private var cancellables = Set<AnyCancellable>()

    /// Whether the window is being closed to return to docked mode.
    /// When true, windowWillClose won't set mode to hidden.
    private var isReturningToDock = false

    // MARK: - Initialization

    /// Creates a reference pane window controller.
    ///
    /// - Parameters:
    ///   - parentWindowState: The WindowState of the browser window that spawned this.
    ///   - environment: The environment to inject into the hosted SwiftUI view.
    init(parentWindowState: WindowState, environment: RefraxEnvironment) {
        self.parentWindowState = parentWindowState
        self.environment = environment

        let window = ReferencePaneWindow()
        super.init(window: window)

        window.delegate = self
        setupContentView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Setup

    private func setupContentView() {
        guard let window else { return }

        let hostingController = NSHostingController(
            rootView: ReferencePaneWindowContentView()
                .refraxEnvironment(environment),
        )

        window.contentViewController = hostingController
    }

    /// Configures and shows the window.
    ///
    /// - Parameters:
    ///   - size: Initial size for the window.
    ///   - sourceWindow: The parent browser window to position relative to.
    func showWindow(size: NSSize, relativeTo sourceWindow: NSWindow?) {
        guard let window else { return }

        window.setContentSize(size)

        if let sourceWindow {
            // Position to the right of the source window
            let sourceFrame = sourceWindow.frame
            let newOrigin = NSPoint(
                x: sourceFrame.maxX + 20,
                y: sourceFrame.midY - size.height / 2,
            )
            window.setFrameOrigin(newOrigin)

            // Add as child window so it stays above the parent
            sourceWindow.addChildWindow(window, ordered: .above)
        } else {
            window.center()
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window and returns to docked mode.
    ///
    /// Called from the toolbar's "Return to sidebar" button.
    func returnToDock() {
        isReturningToDock = true
        // Note: We don't auto-select a reference tab here. If no tab is selected,
        // the docked pane will show the tab selector in the empty state.

        // Close the window first. The mode change and ownership claim happen
        // in windowWillClose after the window's view hierarchy is torn down.
        // This prevents a race condition where setActiveMode is called while
        // the WebView is still in the closing window's hierarchy.
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_: NSWindow, to frameSize: NSSize) -> NSSize {
        var newSize = frameSize
        newSize.width = max(newSize.width, ReferencePaneWindow.minimumWidth)
        newSize.height = max(newSize.height, ReferencePaneWindow.minimumHeight)
        return newSize
    }

    func windowWillClose(_: Notification) {
        // Clear the window flag immediately so the docked view can take over
        parentWindowState.hasReferencePaneWindow = false

        if isReturningToDock {
            // Defer the inspector expansion and ownership claim to the next run loop iteration.
            // This ensures the window's view hierarchy is fully torn down before the
            // docked view tries to claim the WebView, preventing a race condition.
            DispatchQueue.main.async { [self] in
                claimOwnershipForDockedPane()
                parentWindowState.isInspectorCollapsed = false
            }
        }

        isReturningToDock = false
    }

    // MARK: - Private Helpers

    private func claimOwnershipForDockedPane() {
        guard
            let space = parentWindowState.activeSpace,
            let activeRefTabID = parentWindowState.activeReferenceTabID,
            let activeTab = space.referenceTabs.first(where: { $0.id == activeRefTabID }),
            let webPage = environment.tabManager.pagePool.existingPage(for: activeTab.activePage)
        else { return }

        webPage.claimOwnership(for: parentWindowState)
    }
}
