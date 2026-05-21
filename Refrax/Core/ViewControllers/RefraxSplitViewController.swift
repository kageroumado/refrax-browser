import AppKit

/// Custom split view controller that intercepts sidebar and inspector toggle actions.
///
/// The native `NSToolbarToggleSidebarItem` sends `toggleSidebar:` directly to the
/// `NSSplitViewController` in the responder chain. By subclassing and overriding
/// these methods, we can provide custom behavior like smooth overlay transitions.
final class RefraxSplitViewController: NSSplitViewController {
    /// Called when the sidebar toggle action is triggered.
    ///
    /// Set this closure to intercept the toggle and provide custom behavior.
    /// If nil, the default `NSSplitViewController` behavior is used.
    var onToggleSidebar: (() -> Void)?

    /// Called when the inspector toggle action is triggered.
    ///
    /// Set this closure to intercept the toggle and provide custom behavior.
    /// If nil, the default `NSSplitViewController` behavior is used.
    var onToggleInspector: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        disableSidebarBackdrop()
    }

    override func toggleSidebar(_ sender: Any?) {
        if let handler = onToggleSidebar {
            handler()
        } else {
            super.toggleSidebar(sender)
        }
    }

    override func toggleInspector(_ sender: Any?) {
        if let handler = onToggleInspector {
            handler()
        } else {
            super.toggleInspector(sender)
        }
    }

    // MARK: - Sidebar Backdrop Prevention

    /// Disables the sidebar's built-in `CABackdropLayer` by clearing the vibrancy flag.
    ///
    /// NSSplitViewItem creates a per-sidebar `NSVisualEffectView` (containing a
    /// `CABackdropLayer`) when `_hasBaseVibrancyEffect` is YES. The window provides
    /// its own full-width backdrop via `WindowBackgroundView`, so this per-sidebar
    /// backdrop is redundant and causes corner radius mismatches (8 vs 18).
    ///
    /// By clearing the flag on both the item and its wrapper, then calling
    /// `_updateEffectViewState`, AppKit tears down the already-created `_effectView`
    /// and won't recreate it.
    private func disableSidebarBackdrop() {
        guard let sidebarItem = splitViewItems.first else { return }

        sidebarItem._setHasBaseVibrancyEffect(false)

        if let wrapperView = sidebarItem._splitViewItemWrapperView {
            wrapperView.hasBaseVibrancyEffect = false
            wrapperView._updateEffectViewState()
        }
    }
}
