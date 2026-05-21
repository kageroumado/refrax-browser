import AppKit

/// Invisible detector along the left edge that triggers sidebar overlay reveal animation.
///
/// ## Behavior
///
/// **When sidebar is collapsed:**
/// 1. **Cursor approaches edge** (0-10pt from left):
///    - Sidebar overlay slides out proportionally using cubic ease-in curve
///    - Progress = (1 - x/10)³ for smooth acceleration
///    - Follows cursor position in real-time
///
/// 2. **Cursor crosses midpoint** (>5pt into activation zone):
///    - Sidebar snaps to fully visible with spring animation
///    - Detector expands to full sidebar width to maintain visibility
///    - State transitions to "triggered"
///
/// 3. **Cursor leaves area**:
///    - If not yet triggered: immediately cancel and hide
///    - If triggered: wait 0.3s (tolerance) before hiding
///    - Allows user to briefly exit without dismissing
///
/// **When sidebar is expanded:**
/// - Detector is disabled (zero width)
/// - All animations are cancelled
/// - Overlay instantly hidden
///
/// ## Tutorial Peek
///
/// On first sidebar collapse, automatically shows a brief peek animation
/// (20pt slide-out for 2s) to teach users about the hover feature.
///
/// This view dynamically resizes based on sidebar state:
/// - Width = 0 when sidebar is expanded (tracking disabled)
/// - Width = activationWidth (1/3 of sidebar) when collapsed and idle
/// - Width = sidebarWidth when overlay is triggered (allows mouse to stay within overlay)
final class SidebarHoverTrackingView: NSView {
    /// Called when mouse moves within the tracking area with window coordinates
    var onMouseMoved: ((NSPoint) -> Void)?

    /// Called when mouse exits the tracking area
    var onMouseExited: (() -> Void)?

    /// Called when the overlay triggered state changes.
    /// The callback receives `true` when triggered, `false` when dismissed.
    var onOverlayTriggeredChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    /// Whether the overlay is currently triggered (expanded to full width).
    ///
    /// When triggered, this view:
    /// 1. Immediately sets the arrow cursor
    /// 2. Registers a cursor rect to maintain the arrow cursor while mouse is in this view
    /// 3. Notifies the window controller to block mouse move events to WebKit
    var isOverlayTriggered = false {
        didSet {
            guard isOverlayTriggered != oldValue else { return }

            if isOverlayTriggered {
                // Immediately set arrow cursor to override any existing cursor
                NSCursor.arrow.set()
            }

            // Notify callback to block/unblock mouse move events to WebKit
            onOverlayTriggeredChanged?(isOverlayTriggered)

            // Update cursor rects to claim cursor control for this view's area
            window?.invalidateCursorRects(for: self)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil,
        )

        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        // When overlay is triggered, claim the arrow cursor for our entire bounds
        if isOverlayTriggered {
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        // When overlay is triggered, always show arrow cursor in this view
        if isOverlayTriggered {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        onMouseMoved?(locationInWindow)
    }

    override func mouseExited(with _: NSEvent) {
        onMouseExited?()
    }

    /// Pass through all clicks and interactions to views below
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
