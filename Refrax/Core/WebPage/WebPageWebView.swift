import Foundation
import WebKit

// MARK: - WebPageWebView

/// A WKWebView subclass specialized for SwiftUI WebPage integration.
///
/// `WebPageWebView` provides additional capabilities needed for the SwiftUI `WebView`:
/// - Delegate protocol for find interaction events (iOS) and scroll geometry updates
/// - Platform-agnostic scrolling APIs (bounce behavior, content offset)
/// - Scroll geometry update management
///
/// This class mirrors WebKit's internal `WebPageWebView` to maintain API compatibility
/// with the official SwiftUI WebView implementation.
///
/// ## Design Notes
///
/// WebKit uses this subclass internally to:
/// 1. Disable platform find UI (`_usePlatformFindUI = false` on macOS) in favor of custom find bar
/// 2. Forward find interaction events to the Cocoa adapter for state tracking
/// 3. Provide unified scrolling APIs that work across iOS and macOS
/// 4. Track scroll geometry changes for SwiftUI bindings
final class WebPageWebView: WKWebView {
    // MARK: - Delegate

    /// The delegate to receive find interaction and scroll geometry events.
    weak var delegate: (any Delegate)?

    // MARK: - Link Preview

    /// The link preview manager for Shift+Click and Force Touch link previews.
    ///
    /// Set by ``WebPage`` during initialization when link preview is enabled.
    /// Stored here (rather than using objc associated objects) because we own this subclass.
    var linkPreviewManager: LinkPreviewManager?

    // MARK: - Initialization

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)

        #if os(macOS)
            // Disable platform find UI - we use a custom find bar via CocoaWebViewAdapter
            _usePlatformFindUI = false

            // NOTE: Do NOT set _usesAutomaticContentInsetBackgroundFill here!
            // The setter triggers setClientImplicitlyRequestedTopScrollPocket() which calls
            // updateScrollPocket(). If called with topContentInset=0, the pocket won't be
            // created. Later calls to _setObscuredContentInsets will early-return because
            // the flag is already set, so updateScrollPocket() never gets called again.
            //
            // Instead, let CocoaWebViewAdapter control this property. The adapter applies
            // insets FIRST (which triggers updateScrollPocket with correct inset), then
            // sets _usesAutomaticContentInsetBackgroundFill to update the pocket style.
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Scroll Geometry

    /// Notifies the delegate that scroll geometry changed.
    ///
    /// Called by the UI delegate adapter when WebKit reports geometry changes.
    func geometryDidChange(_ geometry: WKScrollGeometryAdapter) {
        delegate?.geometryDidChange(geometry)
    }

    /// Enables or disables scroll geometry update callbacks.
    ///
    /// When enabled, the UI delegate will receive geometry change events that are
    /// forwarded to `geometryDidChange(_:)`.
    ///
    /// - Parameter value: Whether to receive scroll geometry updates.
    func setNeedsScrollGeometryUpdates(_ value: Bool) {
        _setNeedsScrollGeometryUpdates(value)
    }

    // MARK: - Visual Identification

    /// Override the name shown in the visual identification overlay for debugging.
    override var _nameForVisualIdentificationOverlay: String {
        "WebView (SwiftUI)"
    }
}

// MARK: - Delegate Protocol

extension WebPageWebView {
    /// Delegate protocol for receiving events from `WebPageWebView`.
    ///
    /// Implement this protocol on the view adapter that hosts the web view to receive:
    /// - Find interaction lifecycle events (iOS)
    /// - Text replacement capability queries (iOS)
    /// - Scroll geometry change notifications
    protocol Delegate: AnyObject {
        #if os(iOS)
            /// Called when a find interaction session begins.
            func findInteraction(_ interaction: UIFindInteraction, didBegin session: UIFindSession)

            /// Called when a find interaction session ends.
            func findInteraction(_ interaction: UIFindInteraction, didEnd session: UIFindSession)

            /// Returns whether the view supports text replacement.
            func supportsTextReplacement() -> Bool
        #endif

        /// Called when the scroll geometry changes.
        ///
        /// - Parameter geometry: The new scroll geometry values.
        func geometryDidChange(_ geometry: WKScrollGeometryAdapter)
    }
}

// MARK: - Platform-Agnostic Scrolling

extension WebPageWebView {
    #if os(iOS)

        /// Whether the scroll view always bounces vertically.
        var alwaysBounceVertical: Bool {
            get { scrollView.alwaysBounceVertical }
            set { scrollView.alwaysBounceVertical = newValue }
        }

        /// Whether the scroll view always bounces horizontally.
        var alwaysBounceHorizontal: Bool {
            get { scrollView.alwaysBounceHorizontal }
            set { scrollView.alwaysBounceHorizontal = newValue }
        }

        /// Whether the scroll view bounces vertically.
        var bouncesVertically: Bool {
            get { scrollView.bouncesVertically }
            set { scrollView.bouncesVertically = newValue }
        }

        /// Whether the scroll view bounces horizontally.
        var bouncesHorizontally: Bool {
            get { scrollView.bouncesHorizontally }
            set { scrollView.bouncesHorizontally = newValue }
        }

        /// Whether magnification (pinch-to-zoom) is allowed.
        override var allowsMagnification: Bool {
            get { _allowsMagnification }
            set { _allowsMagnification = newValue }
        }

        /// Sets the content offset with optional animation.
        ///
        /// - Parameters:
        ///   - x: The new X offset, or `nil` to keep current.
        ///   - y: The new Y offset, or `nil` to keep current.
        ///   - animated: Whether to animate the change.
        func setContentOffset(x: Double?, y: Double?, animated: Bool) {
            let currentOffset = scrollView.contentOffset
            let newOffset = CGPoint(x: x ?? currentOffset.x, y: y ?? currentOffset.y)
            scrollView.setContentOffset(newOffset, animated: animated)
        }

        /// Scrolls to the specified edge.
        ///
        /// - Parameters:
        ///   - edge: The edge to scroll to.
        ///   - animated: Whether to animate the scroll.
        func scrollTo(edge: NSDirectionalRectEdge, animated: Bool) {
            _scroll(to: _WKRectEdge(edge), animated: animated)
        }

    #else // macOS

        /// Whether the scroll view always bounces vertically.
        ///
        /// On macOS, this maps to the private `_alwaysBounceVertical` property.
        var alwaysBounceVertical: Bool {
            get { _alwaysBounceVertical }
            set { _alwaysBounceVertical = newValue }
        }

        /// Whether the scroll view always bounces horizontally.
        ///
        /// On macOS, this maps to the private `_alwaysBounceHorizontal` property.
        var alwaysBounceHorizontal: Bool {
            get { _alwaysBounceHorizontal }
            set { _alwaysBounceHorizontal = newValue }
        }

        /// Whether the scroll view bounces vertically.
        ///
        /// On macOS, this uses the rubberbanding enabled flags.
        var bouncesVertically: Bool {
            get {
                let edges = _rubberBandingEnabled
                return edges.contains(_WKRectEdge.top) && edges.contains(_WKRectEdge.bottom)
            }
            set {
                var edges = _rubberBandingEnabled
                if newValue {
                    edges.insert(_WKRectEdge.top)
                    edges.insert(_WKRectEdge.bottom)
                } else {
                    edges.remove(_WKRectEdge.top)
                    edges.remove(_WKRectEdge.bottom)
                }
                _rubberBandingEnabled = edges
            }
        }

        /// Whether the scroll view bounces horizontally.
        ///
        /// On macOS, this uses the rubberbanding enabled flags.
        var bouncesHorizontally: Bool {
            get {
                let edges = _rubberBandingEnabled
                return edges.contains(_WKRectEdge.left) && edges.contains(_WKRectEdge.right)
            }
            set {
                var edges = _rubberBandingEnabled
                if newValue {
                    edges.insert(_WKRectEdge.left)
                    edges.insert(_WKRectEdge.right)
                } else {
                    edges.remove(_WKRectEdge.left)
                    edges.remove(_WKRectEdge.right)
                }
                _rubberBandingEnabled = edges
            }
        }

        /// Sets the content offset with optional animation.
        ///
        /// - Parameters:
        ///   - x: The new X offset, or `nil` to keep current.
        ///   - y: The new Y offset, or `nil` to keep current.
        ///   - animated: Whether to animate the change.
        func setContentOffset(x: Double?, y: Double?, animated: Bool) {
            _setContentOffsetX(
                x.map(NSNumber.init(value:)),
                y: y.map(NSNumber.init(value:)),
                animated: animated,
            )
        }

        /// Scrolls to the specified edge.
        ///
        /// - Parameters:
        ///   - edge: The edge to scroll to.
        ///   - animated: Whether to animate the scroll.
        func scrollTo(edge: NSDirectionalRectEdge, animated: Bool) {
            _scroll(to: _WKRectEdge(edge), animated: animated)
        }

    #endif
}

// MARK: - _WKRectEdge Extension

extension _WKRectEdge {
    /// Creates a `_WKRectEdge` from `NSDirectionalRectEdge`.
    init(_ edge: NSDirectionalRectEdge) {
        var result: _WKRectEdge = []
        if edge.contains(.top) { result.insert(.top) }
        if edge.contains(.bottom) { result.insert(.bottom) }
        if edge.contains(.leading) { result.insert(.left) }
        if edge.contains(.trailing) { result.insert(.right) }
        self = result
    }
}

// MARK: - WKScrollGeometryAdapter

/// Adapter wrapping WebKit's private scroll geometry type for public use.
///
/// This provides a stable interface for scroll geometry data that can be exposed
/// through the delegate pattern without depending on private WebKit types.
struct WKScrollGeometryAdapter {
    /// The size of the scroll view container.
    let containerSize: CGSize

    #if canImport(UIKit)
        /// The edge insets for the content (iOS).
        let contentInsets: UIEdgeInsets
    #else
        /// The edge insets for the content (macOS).
        let contentInsets: NSEdgeInsets
    #endif

    /// The current scroll offset of the content.
    let contentOffset: CGPoint

    /// The total size of the scrollable content.
    let contentSize: CGSize

    init(_ geometry: WKScrollGeometry) {
        self.containerSize = geometry.containerSize
        self.contentInsets = geometry.contentInsets
        self.contentOffset = geometry.contentOffset
        self.contentSize = geometry.contentSize
    }
}
