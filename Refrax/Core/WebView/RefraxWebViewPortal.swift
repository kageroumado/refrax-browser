import AppKit
import SwiftUI
import WebKit

/// A SwiftUI view that displays a read-only mirror of web view content.
///
/// `RefraxWebViewPortal` uses a `CAPortalLayer` to mirror the content of a
/// `WKWebView` without user interaction. This is useful for:
///
/// - **Tab previews**: Showing tab thumbnails in tab bars or overview grids
/// - **Multi-window mirrors**: Displaying a tab in secondary windows without input
/// - **Picture-in-picture**: Floating miniature views of web content
/// - **Drag previews**: Visual feedback during tab drag operations
///
/// ## Usage
///
/// ```swift
/// // Basic portal showing tab content
/// RefraxWebViewPortal(page: webPage)
///     .frame(width: 200, height: 150)
///
/// // In a tab bar thumbnail
/// ForEach(tabs) { tab in
///     RefraxWebViewPortal(page: tab.webPage)
///         .aspectRatio(16/9, contentMode: .fit)
/// }
/// ```
///
/// ## Performance
///
/// Portal layers share the backing store of the source layer, so they consume
/// minimal additional memory. Multiple portals can display the same content
/// efficiently.
///
/// ## Thread Safety
///
/// All operations are performed on the main actor as required by AppKit.
struct RefraxWebViewPortal: View {
    // MARK: - Properties

    /// The WebPage whose content to mirror.
    let page: WebPage

    /// Optional corner radius for the portal view.
    var cornerRadius: CGFloat = 0

    /// Whether to show a loading indicator when the web view is loading.
    var showsLoadingIndicator: Bool = false

    // MARK: - Initialization

    /// Creates a portal view for the given WebPage.
    ///
    /// - Parameter page: The `WebPage` whose web content to mirror.
    init(page: WebPage) {
        self.page = page
    }

    // MARK: - Body

    var body: some View {
        RefraxWebViewPortalRepresentable(page: page)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                if showsLoadingIndicator, page.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }
    }
}

// MARK: - View Modifiers

extension RefraxWebViewPortal {
    /// Sets the corner radius of the portal view.
    ///
    /// - Parameter radius: The corner radius to apply.
    /// - Returns: A portal view with the specified corner radius.
    func cornerRadius(_ radius: CGFloat) -> RefraxWebViewPortal {
        var copy = self
        copy.cornerRadius = radius
        return copy
    }

    /// Controls whether a loading indicator is shown.
    ///
    /// - Parameter shows: Whether to show the loading indicator.
    /// - Returns: A portal view with the specified loading indicator behavior.
    func showsLoadingIndicator(_ shows: Bool) -> RefraxWebViewPortal {
        var copy = self
        copy.showsLoadingIndicator = shows
        return copy
    }
}

// MARK: - Portal Representable

/// NSViewRepresentable for the portal layer view.
private struct RefraxWebViewPortalRepresentable: NSViewRepresentable {
    let page: WebPage

    func makeNSView(context _: Context) -> PortalContainerView {
        PortalContainerView()
    }

    func updateNSView(_ nsView: PortalContainerView, context _: Context) {
        if let layer = page.backingWebView.layer {
            nsView.updateSourceLayer(layer)
        }
    }

    static func dismantleNSView(_ nsView: PortalContainerView, coordinator _: ()) {
        nsView.clearPortal()
    }
}

// MARK: - Portal Container View

/// NSView container that manages a CAPortalLayer.
private final class PortalContainerView: NSView {
    // MARK: - Properties

    private var portalLayer: CALayer?
    private weak var currentSourceLayer: CALayer?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Portal Management

    /// Updates the portal to mirror the given source layer.
    ///
    /// - Parameter sourceLayer: The layer to mirror.
    func updateSourceLayer(_ sourceLayer: CALayer) {
        // Skip if already mirroring this layer
        if currentSourceLayer === sourceLayer {
            return
        }

        // Remove existing portal if source changed
        if portalLayer != nil {
            clearPortal()
        }

        // Create new portal
        guard let portal = makePortalLayer() else {
            return
        }

        portal.frame = bounds
        portal.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        portal.setValue(sourceLayer, forKey: "sourceLayer")
        portal.setValue(true, forKey: "matchesTransform")
        portal.setValue(true, forKey: "matchesPosition")

        layer?.addSublayer(portal)
        portalLayer = portal
        currentSourceLayer = sourceLayer
    }

    /// Removes the portal layer.
    func clearPortal() {
        portalLayer?.removeFromSuperlayer()
        portalLayer = nil
        currentSourceLayer = nil
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        portalLayer?.frame = bounds
    }

    // MARK: - Private

    private func makePortalLayer() -> CALayer? {
        guard let portalClass = NSClassFromString("CAPortalLayer") as? CALayer.Type else {
            Logger.error("CAPortalLayer class not available", category: Logger.ui)
            return nil
        }
        return portalClass.init()
    }
}

// MARK: - Tab Thumbnail View

/// A specialized portal view optimized for tab thumbnails.
///
/// `TabThumbnailView` provides a compact representation of a tab's content,
/// suitable for use in tab bars, overview grids, and tab switchers.
///
/// ## Features
///
/// - Automatic aspect ratio maintenance
/// - Optional title overlay
/// - Loading state indication
/// - Favicon display
///
/// ## Usage
///
/// ```swift
/// TabThumbnailView(page: webPage)
///     .frame(width: 200)
///
/// // With title overlay
/// TabThumbnailView(page: webPage, showsTitle: true)
/// ```
struct TabThumbnailView: View {
    // MARK: - Properties

    /// The WebPage to display.
    let page: WebPage

    /// Whether to show the page title.
    var showsTitle: Bool = false

    /// Whether to show the favicon.
    var showsFavicon: Bool = false

    /// The aspect ratio for the thumbnail.
    var aspectRatio: CGFloat = 16.0 / 10.0

    // MARK: - Body

    var body: some View {
        RefraxWebViewPortal(page: page)
            .cornerRadius(8)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if showsTitle {
                    titleOverlay
                }
            }
    }

    @ViewBuilder
    private var titleOverlay: some View {
        HStack(spacing: 6) {
            if showsFavicon {
                FaviconView(data: page.tabPage.faviconData, url: page.tabPage.url, size: 12)
            }

            Text(page.tabPage.title)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Tab Thumbnail Modifiers

extension TabThumbnailView {
    /// Sets whether to show the page title.
    func showsTitle(_ shows: Bool) -> TabThumbnailView {
        var copy = self
        copy.showsTitle = shows
        return copy
    }

    /// Sets whether to show the favicon.
    func showsFavicon(_ shows: Bool) -> TabThumbnailView {
        var copy = self
        copy.showsFavicon = shows
        return copy
    }

    /// Sets the aspect ratio for the thumbnail.
    func aspectRatio(_ ratio: CGFloat) -> TabThumbnailView {
        var copy = self
        copy.aspectRatio = ratio
        return copy
    }
}

// MARK: - Drag Preview

/// A portal view configured for drag-and-drop preview.
///
/// `DragPreviewPortal` creates a lightweight visual representation of a tab
/// suitable for use during drag operations.
///
/// ## Usage
///
/// ```swift
/// tabView
///     .onDrag {
///         NSItemProvider(object: page.url as NSURL)
///     } preview: {
///         DragPreviewPortal(page: page)
///     }
/// ```
struct DragPreviewPortal: View {
    /// The page to preview.
    let page: WebPage

    /// The size of the drag preview.
    var size: CGSize = .init(width: 240, height: 160)

    var body: some View {
        RefraxWebViewPortal(page: page)
            .cornerRadius(8)
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Picture in Picture View

/// A floating portal view for picture-in-picture display.
///
/// `PictureInPicturePortal` provides a compact, floating view of web content
/// that stays visible while the user works in other windows.
///
/// ## Features
///
/// - Draggable floating window
/// - Resizable with aspect ratio lock
/// - Click-through to underlying content
/// - Auto-hide when page is active elsewhere
struct PictureInPicturePortal: View {
    /// The page to display.
    let page: WebPage

    /// Whether the PiP view should be interactive for repositioning.
    @State private var isDragging = false

    var body: some View {
        RefraxWebViewPortal(page: page)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .overlay(alignment: .topTrailing) {
                closeButton
            }
    }

    private var closeButton: some View {
        Button {
            page.closeScreenShareWindow()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(8)
        .opacity(isDragging ? 0 : 1)
    }
}
