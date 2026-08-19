import AppKit
import Observation

/// Manages quick previews for favorites using Option+Click.
///
/// When a user Option+Clicks on a favorite, this manager shows a floating
/// preview panel displaying the page content. The preview uses the existing
/// `LinkPreviewPanel` infrastructure.
///
/// ## Behavior
///
/// - **Option+Click**: Shows preview panel for the favorite
/// - **Normal click on favorite while preview is open**: Closes preview and activates the tab
/// - **"Open in Tab" button**: Activates the live favorite tab (or creates new tab for shortcuts)
/// - **"Open in Glimpse"**: Opens the URL in a Glimpse window
///
/// ## Integration
///
/// The preview observes when its source tab becomes active. If the user
/// activates the tab (e.g., by clicking the favorite normally), the preview
/// automatically closes.
@Observable
final class FavoritePreviewManager {
    // MARK: - Dependencies

    private unowned let tabManager: TabManager
    private unowned let windowManager: WindowManager

    // MARK: - State

    /// The currently active preview panel, if any.
    private var previewPanel: LinkPreviewPanel?

    /// The tab being previewed (for live favorites).
    private(set) var previewingTab: Tab?

    /// The URL being previewed.
    private(set) var previewingURL: URL?

    /// Whether a preview is currently visible.
    var isPreviewVisible: Bool {
        previewPanel != nil
    }

    // MARK: - Initialization

    init(tabManager: TabManager, windowManager: WindowManager) {
        self.tabManager = tabManager
        self.windowManager = windowManager
        tabManager.favoritePreviewManager = self
    }

    // MARK: - Preview Actions

    /// Shows a preview for a live favorite's tab.
    ///
    /// - Parameters:
    ///   - tab: The live favorite tab to preview.
    ///   - originRect: The screen rect of the favorite tile (for animation origin).
    ///   - windowState: The window state for positioning the panel.
    func showPreview(
        for tab: Tab,
        originRect: NSRect,
        in windowState: WindowState,
    ) {
        showPreviewPanel(
            url: tab.activePage.url,
            title: tab.displayTitle,
            sourceTab: tab,
            originRect: originRect,
            windowState: windowState,
        )
    }

    /// Shows a preview for a bookmark shortcut.
    ///
    /// - Parameters:
    ///   - bookmark: The bookmark to preview.
    ///   - originRect: The screen rect of the favorite tile (for animation origin).
    ///   - windowState: The window state for positioning the panel.
    func showPreview(
        for bookmark: Bookmark,
        originRect: NSRect,
        in windowState: WindowState,
    ) {
        showPreviewPanel(
            url: bookmark.url,
            title: bookmark.title,
            sourceTab: nil,
            originRect: originRect,
            windowState: windowState,
        )
    }

    /// Dismisses the current preview.
    func dismissPreview() {
        if let panel = previewPanel {
            panel.parent?.removeChildWindow(panel)
            panel.close()
        }
        previewPanel = nil
        previewingTab = nil
        previewingURL = nil
    }

    /// Called by ``TabManager`` whenever the active tab changes.
    ///
    /// The preview is anchored to the tab that was active when it opened, so any
    /// activation invalidates it: activating the previewed favorite replaces the
    /// preview with the real tab, and switching to any other tab would leave the
    /// panel floating detached over unrelated content.
    func handleActiveTabChange() {
        dismissPreview()
    }

    // MARK: - Private Implementation

    private func showPreviewPanel(
        url: URL,
        title: String,
        sourceTab: Tab?,
        originRect: NSRect,
        windowState: WindowState,
    ) {
        // Dismiss any existing preview
        dismissPreview()

        // Get the parent tab for creating the preview page
        guard let activeTab = windowState.activeTab else {
            Logger.warning("Cannot show preview without active tab", category: Logger.ui)
            return
        }

        // Create a preview page through the full pipeline
        guard let previewWebPage = tabManager.createPreviewPage(for: url, in: activeTab) else {
            Logger.error("Failed to create preview page for \(url)", category: Logger.ui)
            return
        }

        // Calculate panel size and position
        guard let window = windowState.window else { return }

        let panelSize = calculatePreviewSize(for: window)
        let finalFrame = calculatePanelFrame(size: panelSize, in: window)

        let panel = LinkPreviewPanel(
            webPage: previewWebPage,
            size: panelSize,
            originRect: originRect,
            finalFrame: finalFrame,
            onClose: { [weak self, weak activeTab] in
                if let activeTab {
                    self?.tabManager.clearPreviewPage(for: activeTab)
                }
                self?.previewPanel = nil
                self?.previewingTab = nil
                self?.previewingURL = nil
            },
            onOpenInNewTab: { [weak self, sourceTab] in
                self?.handleOpenInTab(sourceTab: sourceTab, url: url, windowState: windowState)
            },
            onShare: { [weak previewWebPage] shareButton in
                guard let url = previewWebPage?.url else { return }
                let picker = NSSharingServicePicker(items: [url])
                picker.show(relativeTo: .zero, of: shareButton, preferredEdge: .minY)
            },
        )

        // Position and show with animation.
        // Attach as a child window so the panel stays above only Refrax and
        // follows the browser window through ordering changes.
        panel.setFrame(finalFrame, display: false)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.animateAppearance()

        previewPanel = panel
        previewingTab = sourceTab
        previewingURL = url

        Logger.info("Showing favorite preview for '\(title)'", category: Logger.ui)
    }

    private func handleOpenInTab(sourceTab: Tab?, url: URL, windowState: WindowState) {
        if let sourceTab {
            // For live favorites, activate the existing tab
            tabManager.setActiveTab(sourceTab, in: windowState)
        } else {
            // For shortcuts, create a new tab
            tabManager.createTab(
                url: url,
                in: windowState.activeSpace,
                makeActive: true,
                loadImmediately: true,
            )
        }
        dismissPreview()
    }

    private func calculatePreviewSize(for window: NSWindow) -> NSSize {
        // Try to get size from splitViewController's content area
        if let windowController = window.windowController as? RefraxWindowController {
            let splitVC = windowController.splitViewController
            if splitVC.splitViewItems.count > 1 {
                let contentItem = splitVC.splitViewItems[1]
                let contentFrame = contentItem.viewController.view.frame
                return NSSize(
                    width: contentFrame.width * 0.8,
                    height: contentFrame.height * 0.9,
                )
            }
        }

        // Fallback to window-based sizing
        return NSSize(
            width: window.frame.width * 0.6,
            height: window.frame.height * 0.7,
        )
    }

    private func calculatePanelFrame(size: NSSize, in window: NSWindow) -> NSRect {
        // Get the content area frame in screen coordinates
        let contentFrame: NSRect
        if let windowController = window.windowController as? RefraxWindowController {
            let splitVC = windowController.splitViewController
            if splitVC.splitViewItems.count > 1 {
                let contentItem = splitVC.splitViewItems[1]
                let contentView = contentItem.viewController.view
                let viewFrame = contentView.convert(contentView.bounds, to: nil)
                contentFrame = window.convertToScreen(viewFrame)
            } else {
                contentFrame = window.convertToScreen(window.contentLayoutRect)
            }
        } else {
            contentFrame = window.convertToScreen(window.contentLayoutRect)
        }

        // Center the panel in the content area
        let x = contentFrame.midX - size.width / 2
        let y = contentFrame.midY - size.height / 2

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
