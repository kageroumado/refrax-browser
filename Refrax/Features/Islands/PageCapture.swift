import AppKit

/// Captures what a view shows on screen, right now, from the window server: the same hardware
/// capture the web view adapter takes before it moves a web view, so a page becomes an image
/// in under a millisecond without asking WebKit to render.
nonisolated enum PageCapture {
    /// How long after the window's controls are hidden the window server shows a frame
    /// without them: two frames at 60 Hz. A capture taken after this shows the page alone.
    static let compositingDelay: Duration = .milliseconds(40)

    /// The image of the part of `view` inside the window, from that part's top-left, sized in
    /// points to match it exactly; `nil` when the view is not on a visible window or the
    /// capture fails. A page view may run past the window's edge, so the image is sized from
    /// what the window shows, never from the view's bounds: a 1000 pt image labeled 1016 pt
    /// would stretch the page by 1.6% and the live page would land beside it, not on it.
    @MainActor
    static func image(of view: NSView) -> NSImage? {
        guard let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor,
              view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        var windowID = CGSWindowID(window.windowNumber)
        let options = CGSWindowCaptureOptions(kCGSCaptureIgnoreGlobalClipShape)
        guard let captures = CGSHWCaptureWindowList(CGSMainConnectionID(), &windowID, 1, options),
              let first = (captures as NSArray).firstObject else { return nil }
        let full = first as! CGImage
        let windowBounds = CGRect(origin: .zero, size: window.frame.size)
        let visible = view.convert(view.bounds, to: nil).intersection(windowBounds)
        guard !visible.isEmpty else { return nil }
        let scale = window.backingScaleFactor
        let crop = CGRect(
            x: (visible.origin.x * scale).rounded(),
            y: ((windowBounds.height - visible.maxY) * scale).rounded(),
            width: (visible.width * scale).rounded(),
            height: (visible.height * scale).rounded(),
        )
        guard let cropped = full.cropping(to: crop) else { return nil }
        return NSImage(cgImage: cropped, size: CGSize(width: CGFloat(cropped.width) / scale, height: CGFloat(cropped.height) / scale))
    }
}
