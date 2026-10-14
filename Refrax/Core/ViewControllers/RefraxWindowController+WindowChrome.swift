import AppKit

// MARK: - Window Chrome

extension RefraxWindowController {
    /// Hides AppKit's close, minimize, and zoom buttons: the Control Island draws the window's own.
    func hideStandardWindowButtons() {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(type)?.isHidden = true
        }
        (window?.contentView?.superview as? NSThemeFrame)?.buttonRevealAmount = 0
    }
}
