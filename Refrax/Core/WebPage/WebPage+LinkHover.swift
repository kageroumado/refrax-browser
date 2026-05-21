import Foundation

// MARK: - Link Hover Callback

extension WebPage {
    /// Handles mouse movement over link elements.
    ///
    /// Called by ``WKUIDelegateAdapter`` when WebKit detects the mouse moving
    /// over different elements.
    ///
    /// - Parameter linkURL: The URL of the link under the mouse, or `nil` if not over a link.
    func handleMouseDidMoveOverLink(_ linkURL: URL?) {
        onHoveredLinkChanged?(linkURL)
    }
}
