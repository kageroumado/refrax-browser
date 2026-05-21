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

    private var thumbnailViews: [(view: _WKThumbnailView, position: PanePosition)] = []
    private var layoutType: LayoutType = .single
    private var horizontalDivider: CGFloat = 0.5
    private var verticalDivider: CGFloat = 0.5

    // MARK: - Constants

    private enum Layout {
        static let dividerThickness: CGFloat = 2
    }

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

    // MARK: - Configuration

    /// Configures the adapter with a single thumbnail view.
    ///
    /// - Parameter thumbnailView: The thumbnail view to display.
    func configure(with thumbnailView: _WKThumbnailView) {
        clearThumbnails()

        thumbnailViews = [(thumbnailView, .single)]
        layoutType = .single

        addSubview(thumbnailView)
        thumbnailView.autoresizingMask = [.width, .height]
        thumbnailView.frame = bounds
    }

    /// Configures the adapter with multiple thumbnail views for a multi-page tab.
    ///
    /// - Parameters:
    ///   - views: Array of thumbnail views with their pane positions.
    ///   - configuration: The layout configuration for arranging the views.
    func configure(
        with views: [(view: _WKThumbnailView, position: PanePosition)],
        configuration: LayoutConfiguration,
    ) {
        clearThumbnails()

        thumbnailViews = views
        layoutType = configuration.layoutType
        horizontalDivider = CGFloat(configuration.horizontalDivider)
        verticalDivider = CGFloat(configuration.verticalDivider)

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
        for (view, position) in thumbnailViews {
            view.frame = frameForPosition(position)
        }
    }

    private func frameForPosition(_ position: PanePosition) -> CGRect {
        let size = bounds.size
        let divider = Layout.dividerThickness

        switch layoutType {
        case .single:
            return bounds

        case .split:
            let splitX = size.width * horizontalDivider
            let leftWidth = splitX - divider / 2
            let rightWidth = size.width - splitX - divider / 2

            switch position {
            case .topLeft, .bottomLeft, .single:
                return CGRect(x: 0, y: 0, width: leftWidth, height: size.height)
            case .topRight, .bottomRight:
                return CGRect(x: splitX + divider / 2, y: 0, width: rightWidth, height: size.height)
            }

        case .triple, .quad:
            let splitX = size.width * horizontalDivider
            let splitY = size.height * verticalDivider

            let leftWidth = splitX - divider / 2
            let rightWidth = size.width - splitX - divider / 2
            let bottomHeight = splitY - divider / 2
            let topHeight = size.height - splitY - divider / 2

            switch position {
            case .bottomLeft:
                return CGRect(x: 0, y: 0, width: leftWidth, height: bottomHeight)
            case .bottomRight:
                return CGRect(x: splitX + divider / 2, y: 0, width: rightWidth, height: bottomHeight)
            case .topLeft:
                return CGRect(x: 0, y: splitY + divider / 2, width: leftWidth, height: topHeight)
            case .topRight:
                return CGRect(x: splitX + divider / 2, y: splitY + divider / 2, width: rightWidth, height: topHeight)
            case .single:
                return bounds
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
