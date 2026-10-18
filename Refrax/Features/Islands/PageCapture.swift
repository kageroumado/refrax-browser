import AppKit

/// Captures what a view shows on screen, right now, from the window server: the same hardware
/// capture the web view adapter takes before it moves a web view, so a page becomes an image
/// in under a millisecond without asking WebKit to render.
nonisolated enum PageCapture {
    /// The image of `view`'s bounds as the window shows them, or `nil` when the view is not on
    /// a visible window or the capture fails.
    @MainActor
    static func image(of view: NSView) -> NSImage? {
        guard let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor,
              view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        var windowID = CGSWindowID(window.windowNumber)
        let options = CGSWindowCaptureOptions(kCGSCaptureIgnoreGlobalClipShape)
        guard let captures = CGSHWCaptureWindowList(CGSMainConnectionID(), &windowID, 1, options),
              let first = (captures as NSArray).firstObject else { return nil }
        let full = first as! CGImage
        let inWindow = view.convert(view.bounds, to: nil)
        let scale = window.backingScaleFactor
        let crop = CGRect(
            x: inWindow.origin.x * scale,
            y: (window.frame.height - inWindow.maxY) * scale,
            width: inWindow.width * scale,
            height: inWindow.height * scale,
        )
        guard let cropped = full.cropping(to: crop) else { return nil }
        return NSImage(cgImage: cropped, size: inWindow.size)
    }
}
