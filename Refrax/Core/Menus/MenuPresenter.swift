import AppKit

/// Pops a rendered ``MenuTree`` up from an AppKit view and keeps the menu reachable while it
/// tracks, so the owner can cancel it when the view goes away mid-presentation.
final class MenuPresenter {
    private(set) var presentedMenu: NSMenu?

    /// Shows the tree with its top-left corner at `point` in `view`'s coordinates and returns
    /// when the menu closes. The delegate receives `menuWillOpen` and `menuDidClose`.
    func present(_ tree: MenuTree, at point: NSPoint, in view: NSView, delegate: (any NSMenuDelegate)? = nil) {
        let menu = NSMenuRenderer.menu(tree)
        menu.delegate = delegate
        presentedMenu = menu
        menu.popUp(positioning: nil, at: point, in: view)
        presentedMenu = nil
    }

    func cancel() {
        presentedMenu?.cancelTracking()
    }
}
