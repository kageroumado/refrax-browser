import AppKit
import SwiftUI

/// Describes which portion of a divider is active (for triple layouts)
enum DividerSpan: Equatable, Sendable {
    /// Full span (default for quad/split layouts)
    case full
    /// Only the top/left portion (from start to the crossing divider)
    case firstHalf
    /// Only the bottom/right portion (from the crossing divider to end)
    case secondHalf
}

/// Configuration for which dividers are active and their current positions
struct DividerConfiguration {
    /// Whether the vertical divider (splits left/right) is shown
    var hasVerticalDivider: Bool

    /// Whether the horizontal divider (splits top/bottom) is shown
    var hasHorizontalDivider: Bool

    /// Vertical divider position as a ratio (0-1) of the width
    var verticalDividerRatio: CGFloat

    /// Horizontal divider position as a ratio (0-1) of the height
    var horizontalDividerRatio: CGFloat

    /// Which portion of the vertical divider is active (for triple layouts)
    var verticalDividerSpan: DividerSpan = .full

    /// Which portion of the horizontal divider is active (for triple layouts)
    var horizontalDividerSpan: DividerSpan = .full
}

/// NSViewRepresentable wrapper for DividerTrackingNSView
///
/// This view overlays the web content and handles:
/// - Cursor changes to resize arrows when hovering over divider zones
/// - Drag gesture handling for divider repositioning
/// - Proper hit testing so clicks outside divider zones pass through to web content
struct DividerTrackingView: NSViewRepresentable {
    /// Current divider configuration
    let configuration: DividerConfiguration

    /// Called when a divider drag begins
    let onDragBegan: (DividerType) -> Void

    /// Called during divider drag with the delta from drag start
    let onDragChanged: (DividerType, CGFloat) -> Void

    /// Called when a divider drag ends
    let onDragEnded: (DividerType) -> Void

    func makeNSView(context _: Context) -> DividerTrackingNSView {
        let view = DividerTrackingNSView()
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        updateConfiguration(view)
        return view
    }

    func updateNSView(_ nsView: DividerTrackingNSView, context _: Context) {
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        updateConfiguration(nsView)
    }

    private func updateConfiguration(_ view: DividerTrackingNSView) {
        view.hasVerticalDivider = configuration.hasVerticalDivider
        view.hasHorizontalDivider = configuration.hasHorizontalDivider
        view.verticalDividerRatio = configuration.verticalDividerRatio
        view.horizontalDividerRatio = configuration.horizontalDividerRatio
        view.verticalDividerSpan = configuration.verticalDividerSpan
        view.horizontalDividerSpan = configuration.horizontalDividerSpan
        view.updateTrackingAreasIfNeeded()
    }
}

// MARK: - DividerTrackingNSView

/// AppKit view that handles cursor tracking and drag gestures for pane dividers.
///
/// This view solves the problem of WKWebView overriding cursor changes by using
/// separate tracking areas for each divider zone with cursor push/pop management.
///
/// ## How It Works
///
/// 1. **Cursor Control**: Creates separate tracking areas for each divider zone (not the whole view).
///    Uses `NSCursor.push()` when entering a zone and `pop()` when exiting to maintain cursor
///    state against WKWebView's continuous cursor updates.
///
/// 2. **Hit Testing**: Only claims hits within the divider interaction zones (15px wide/tall).
///    All other clicks pass through to the web content beneath.
///
/// 3. **Drag Handling**: Handles `mouseDown`/`mouseDragged`/`mouseUp` at the AppKit level
///    for reliable drag tracking that doesn't compete with WKWebView's event handling.
final class DividerTrackingNSView: NSView {
    /// Width/height of the interaction zone around each divider
    static let interactionZone: CGFloat = 15

    // MARK: - Configuration

    var hasVerticalDivider = false
    var hasHorizontalDivider = false
    var verticalDividerRatio: CGFloat = 0.5
    var horizontalDividerRatio: CGFloat = 0.5
    var verticalDividerSpan: DividerSpan = .full
    var horizontalDividerSpan: DividerSpan = .full

    // MARK: - Callbacks

    var onDragBegan: ((DividerType) -> Void)?
    var onDragChanged: ((DividerType, CGFloat) -> Void)?
    var onDragEnded: ((DividerType) -> Void)?

    // MARK: - Tracking State

    private var verticalTrackingArea: NSTrackingArea?
    private var horizontalTrackingArea: NSTrackingArea?
    private var activeDrag: DividerType?
    private var dragStartLocation: CGFloat = 0
    /// Which divider zone the cursor is currently in (for push/pop management)
    private var currentHoverZone: DividerType?

    // MARK: - Computed Properties

    /// The x-coordinate of the vertical divider
    private var verticalDividerX: CGFloat {
        bounds.width * verticalDividerRatio
    }

    /// The y-coordinate of the horizontal divider (in flipped coordinates)
    private var horizontalDividerY: CGFloat {
        bounds.height * horizontalDividerRatio
    }

    /// Rect for the vertical divider interaction zone
    ///
    /// For triple layouts, the vertical divider may only span part of the height.
    private var verticalDividerRect: CGRect {
        guard hasVerticalDivider else { return .zero }
        let x = verticalDividerX - Self.interactionZone / 2

        let (rectY, rectHeight): (CGFloat, CGFloat)
        switch verticalDividerSpan {
        case .full:
            rectY = 0
            rectHeight = bounds.height
        case .firstHalf:
            // Top half only (from top to horizontal divider)
            rectY = 0
            rectHeight = horizontalDividerY
        case .secondHalf:
            // Bottom half only (from horizontal divider to bottom)
            rectY = horizontalDividerY
            rectHeight = bounds.height - horizontalDividerY
        }

        return CGRect(x: x, y: rectY, width: Self.interactionZone, height: rectHeight)
    }

    /// Rect for the horizontal divider interaction zone
    ///
    /// For triple layouts, the horizontal divider may only span part of the width.
    private var horizontalDividerRect: CGRect {
        guard hasHorizontalDivider else { return .zero }
        let y = horizontalDividerY - Self.interactionZone / 2

        let (rectX, rectWidth): (CGFloat, CGFloat)
        switch horizontalDividerSpan {
        case .full:
            rectX = 0
            rectWidth = bounds.width
        case .firstHalf:
            // Left half only (from left to vertical divider)
            rectX = 0
            rectWidth = verticalDividerX
        case .secondHalf:
            // Right half only (from vertical divider to right)
            rectX = verticalDividerX
            rectWidth = bounds.width - verticalDividerX
        }

        return CGRect(x: rectX, y: y, width: rectWidth, height: Self.interactionZone)
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    // MARK: - Coordinate System

    /// Use flipped coordinates to match SwiftUI's coordinate system
    override var isFlipped: Bool {
        true
    }

    // MARK: - Tracking Areas

    func updateTrackingAreasIfNeeded() {
        window?.invalidateCursorRects(for: self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas
        if let existing = verticalTrackingArea {
            removeTrackingArea(existing)
            verticalTrackingArea = nil
        }
        if let existing = horizontalTrackingArea {
            removeTrackingArea(existing)
            horizontalTrackingArea = nil
        }

        // Create separate tracking areas for each divider zone
        // This gives AppKit precise information about where cursor changes should happen
        // and prevents competing with WKWebView's whole-view tracking areas

        if hasVerticalDivider {
            let rect = verticalDividerRect
            if rect.width > 0, rect.height > 0 {
                verticalTrackingArea = NSTrackingArea(
                    rect: rect,
                    options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
                    owner: self,
                    userInfo: ["divider": DividerType.vertical],
                )
                addTrackingArea(verticalTrackingArea!)
            }
        }

        if hasHorizontalDivider {
            let rect = horizontalDividerRect
            if rect.width > 0, rect.height > 0 {
                horizontalTrackingArea = NSTrackingArea(
                    rect: rect,
                    options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
                    owner: self,
                    userInfo: ["divider": DividerType.horizontal],
                )
                addTrackingArea(horizontalTrackingArea!)
            }
        }
    }

    // MARK: - Cursor Rects

    override func resetCursorRects() {
        super.resetCursorRects()

        // Add cursor rects for each active divider zone
        // This is a backup mechanism; the primary control is via tracking areas
        if hasVerticalDivider {
            addCursorRect(verticalDividerRect, cursor: .resizeLeftRight)
        }

        if hasHorizontalDivider {
            addCursorRect(horizontalDividerRect, cursor: .resizeUpDown)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        // Get the divider type from the tracking area's userInfo
        guard let userInfo = event.trackingArea?.userInfo,
              let dividerType = userInfo["divider"] as? DividerType
        else {
            super.cursorUpdate(with: event)
            return
        }

        // Reinforce the override cursor on each update
        setOverrideCursor(for: dividerType)
    }

    // MARK: - Mouse Tracking

    override func mouseEntered(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo,
              let dividerType = userInfo["divider"] as? DividerType
        else { return }

        currentHoverZone = dividerType

        // Use the override cursor API - this takes precedence over normal
        // cursor changes, preventing WKWebView from overriding it
        setOverrideCursor(for: dividerType)
    }

    override func mouseExited(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo,
              let dividerType = userInfo["divider"] as? DividerType
        else { return }

        // Only clear if we're exiting the zone we're currently in
        if currentHoverZone == dividerType {
            clearOverrideCursor()
            currentHoverZone = nil
        }
    }

    // MARK: - Override Cursor Helpers

    /// Sets the override cursor for a divider type using the private API.
    /// This cursor takes precedence over normal cursor changes from WKWebView.
    private func setOverrideCursor(for dividerType: DividerType) {
        let cursor: NSCursor = switch dividerType {
        case .vertical: .resizeLeftRight
        case .horizontal: .resizeUpDown
        }
        NSCursor._setOverrideCursor(cursor)
    }

    /// Clears the override cursor and restores normal cursor behavior.
    private func clearOverrideCursor() {
        NSCursor._clearOverrideCursorAndSetArrow()
    }

    // MARK: - Hit Testing

    /// Only claim hits within the divider interaction zones.
    ///
    /// This is critical for allowing clicks on web content to pass through.
    /// Without this, the overlay would block all interaction with the web views.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Convert point to local coordinates
        let localPoint = convert(point, from: superview)

        // Check if point is in any divider zone
        if hasVerticalDivider, verticalDividerRect.contains(localPoint) {
            return self
        }

        if hasHorizontalDivider, horizontalDividerRect.contains(localPoint) {
            return self
        }

        // Not in a divider zone - pass through to views beneath
        return nil
    }

    // MARK: - Mouse Drag Handling

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Determine which divider (if any) was clicked
        // Priority: vertical divider
        if hasVerticalDivider, verticalDividerRect.contains(location) {
            activeDrag = .vertical
            dragStartLocation = location.x
            setOverrideCursor(for: .vertical)
            onDragBegan?(.vertical)
        } else if hasHorizontalDivider, horizontalDividerRect.contains(location) {
            activeDrag = .horizontal
            dragStartLocation = location.y
            setOverrideCursor(for: .horizontal)
            onDragBegan?(.horizontal)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dividerType = activeDrag else { return }

        let location = convert(event.locationInWindow, from: nil)

        // Reinforce the override cursor during drag
        setOverrideCursor(for: dividerType)

        switch dividerType {
        case .vertical:
            let delta = location.x - dragStartLocation
            onDragChanged?(.vertical, delta)
        case .horizontal:
            let delta = location.y - dragStartLocation
            onDragChanged?(.horizontal, delta)
        }
    }

    override func mouseUp(with _: NSEvent) {
        guard let dividerType = activeDrag else { return }

        onDragEnded?(dividerType)
        activeDrag = nil
        dragStartLocation = 0

        // Clear override cursor after drag ends
        // If still in hover zone, mouseEntered will be called again
        if currentHoverZone == nil {
            clearOverrideCursor()
        }
    }
}
