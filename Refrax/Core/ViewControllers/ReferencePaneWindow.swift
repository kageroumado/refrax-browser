import AppKit
import QuartzCore

/// Window for displaying the reference pane as a separate window.
///
/// This window hosts the reference pane content when the user detaches it from
/// the main browser window. It uses a compact toolbar style similar to iOS Safari.
///
/// ## Design
///
/// - Uses `.unifiedCompact` toolbar style for compact toolbar
/// - Titlebar has blur effect via CABackdropLayer
/// - Content extends behind the toolbar (fullSizeContentView)
/// - Uses page theme color when scrolled to top
///
/// ## Lifecycle
///
/// - Created when user clicks "Open in Window" in reference pane
/// - Closed when user closes window or "Return to sidebar" is clicked
/// - On close: Reference pane mode is set to `.hidden` (tabs preserved)
/// - On return to dock: Reference pane mode is set to `.docked`
final class ReferencePaneWindow: NSWindow, NSToolbarDelegate {
    /// Minimum window width to accommodate toolbar with address bar.
    /// Practical minimum ensuring address bar is usable (~200px minimum).
    static let minimumWidth: CGFloat = 450

    /// Minimum window height for usability.
    static let minimumHeight: CGFloat = 400

    /// Returns the max X position of the traffic light buttons (close/minimize/zoom).
    ///
    /// Used by the toolbar view to position content after the traffic lights.
    var trafficLightButtonsMaxX: CGFloat {
        guard let themeFrame = contentView?.superview as? NSThemeFrame else { return 70 }

        let zoomOrigin = themeFrame._zoomButtonOrigin()
        // Zoom button is the rightmost, add button width (~14) plus padding
        return zoomOrigin.x + 14 + 8
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )

        // Use unified toolbar style - positions traffic lights centered in toolbar
        toolbarStyle = .unifiedCompact

        // Hide title text but keep titlebar area with blur
        titleVisibility = .hidden

        // Make titlebar transparent - we'll add our own blur
        titlebarAppearsTransparent = true

        // Allow dragging from the background
        isMovableByWindowBackground = true

        // Not restorable - ephemeral window
        isRestorable = false

        // Minimum and content min size for usability
        minSize = NSSize(width: Self.minimumWidth, height: Self.minimumHeight)
        contentMinSize = NSSize(width: Self.minimumWidth, height: Self.minimumHeight)

        // Add an NSToolbar so traffic lights are positioned correctly (centered in toolbar)
        // The toolbar is invisible - actual controls are in SwiftUI
        setupToolbar()
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "ReferencePaneToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        self.toolbar = toolbar
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier _: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool,
    ) -> NSToolbarItem? {
        nil
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace]
    }
}
