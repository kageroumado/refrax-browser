import AppKit
import WebKit

/// A view that composites one or more `_WKThumbnailView` instances for tab previews.
///
/// `ThumbnailAdapter` handles both single-page and multi-page tab layouts:
/// - **Single page**: Wraps a single `_WKThumbnailView`
/// - **Multi-page**: Arranges multiple `_WKThumbnailView` instances according to layout configuration
///
/// This approach avoids expensive image capture and compositing operations by letting
/// the window server composite the views directly.
final class ThumbnailAdapter: NSView {
    // MARK: - Properties

    private var thumbnailViews: [(view: _WKThumbnailView, pageID: UUID?)] = []
    private var grid = PaneGrid()
    private var configuration: LayoutConfiguration?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-left origin, as the pane grid lays out.
    override var isFlipped: Bool {
        true
    }

    // MARK: - Configuration

    /// Configures the adapter with a single thumbnail view.
    ///
    /// - Parameter thumbnailView: The thumbnail view to display.
    func configure(with thumbnailView: _WKThumbnailView) {
        clearThumbnails()

        thumbnailViews = [(thumbnailView, nil)]
        grid = PaneGrid()
        configuration = nil

        addSubview(thumbnailView)
        thumbnailView.autoresizingMask = [.width, .height]
        thumbnailView.frame = bounds
    }

    /// Configures the adapter with one thumbnail view per pane of a multi-page tab, laid out
    /// as the page lays them out.
    ///
    /// - Parameters:
    ///   - views: Each pane's thumbnail view, by its page.
    ///   - grid: The tab's panes.
    ///   - configuration: The tab's stored layout, for its split ratios.
    func configure(with views: [(view: _WKThumbnailView, pageID: UUID)], grid: PaneGrid, configuration: LayoutConfiguration?) {
        clearThumbnails()

        thumbnailViews = views.map { ($0.view, $0.pageID) }
        self.grid = grid
        self.configuration = configuration

        for (view, _) in views {
            addSubview(view)
        }

        layoutThumbnails()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutThumbnails()
    }

    private func layoutThumbnails() {
        let geometry = PaneGridGeometry(size: bounds.size, configuration: configuration, metrics: .page)
        for (view, pageID) in thumbnailViews {
            if let pageID, let span = grid.span(of: pageID) {
                view.frame = geometry.frame(of: span)
            } else {
                view.frame = bounds
            }
        }
    }

    // MARK: - Cleanup

    private func clearThumbnails() {
        for (view, _) in thumbnailViews {
            view.removeFromSuperview()
        }
        thumbnailViews.removeAll()
    }
}
