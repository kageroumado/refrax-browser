import AppKit

/// A window for displaying a reflected view of a WebPage.
///
/// Participates in the owner/portal WebView swapping mechanism. When this window
/// becomes key, it claims ownership of the WebPage's interactive WebView. Other
/// windows displaying the same page automatically switch to portal mode.
///
/// ## Design
///
/// - Same chrome as `ReferencePaneWindow` (transparent titlebar, frosted glass)
/// - Title shows page title (not hardcoded)
/// - Closable, movable by background
/// - Not restorable across app restarts
final class ReflectedWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true

        // Not restorable - ephemeral window
        isRestorable = false

        // Minimum size for usability
        minSize = NSSize(width: 400, height: 300)
        contentMinSize = NSSize(width: 400, height: 300)
    }
}
