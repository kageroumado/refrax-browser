import AppKit
import SwiftUI

/// Where a divider can be taken hold of: its axis and the area that grabs it, in the page's
/// top-left-origin coordinates.
struct DividerGrip: Equatable {
    let axis: PaneDivider.Axis
    let frame: CGRect
}

/// The grips of a page's dividers: the resize cursor over them and the drag that moves them.
///
/// Clicks outside every grip pass through to the panes beneath.
struct DividerTrackingView: NSViewRepresentable {
    let grips: [DividerGrip]
    /// A drag moved a divider's grip to `location`: an x for a column line, a y for a row line.
    let onDrag: (PaneDivider.Axis, CGFloat) -> Void
    let onDragEnded: (PaneDivider.Axis) -> Void

    func makeNSView(context _: Context) -> DividerTrackingNSView {
        let view = DividerTrackingNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: DividerTrackingNSView, context _: Context) {
        apply(to: view)
    }

    private func apply(to view: DividerTrackingNSView) {
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
        if view.grips != grips {
            view.grips = grips
            view.window?.invalidateCursorRects(for: view)
            view.updateTrackingAreas()
        }
    }
}

/// The AppKit side of ``DividerTrackingView``.
///
/// A web view sets the cursor on every mouse move, so each grip has its own tracking area
/// and sets an override cursor while the pointer is in it; the drag runs at the AppKit level,
/// where it never competes with the web view's own event handling.
final class DividerTrackingNSView: NSView {
    var grips: [DividerGrip] = []
    var onDrag: ((PaneDivider.Axis, CGFloat) -> Void)?
    var onDragEnded: ((PaneDivider.Axis) -> Void)?

    private var trackingAreasByGrip: [NSTrackingArea] = []
    private var activeDrag: PaneDivider.Axis?
    /// The grip the pointer is in, whose cursor is set.
    private var hoveredAxis: PaneDivider.Axis?

    override var isFlipped: Bool {
        true
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreasByGrip {
            removeTrackingArea(area)
        }
        trackingAreasByGrip = grips.filter { !$0.frame.isEmpty }.map { grip in
            let area = NSTrackingArea(
                rect: grip.frame,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
                owner: self,
                userInfo: ["axis": grip.axis == .column ? "column" : "row"],
            )
            addTrackingArea(area)
            return area
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for grip in grips {
            addCursorRect(grip.frame, cursor: cursor(for: grip.axis))
        }
    }

    private func axis(of event: NSEvent) -> PaneDivider.Axis? {
        guard let name = event.trackingArea?.userInfo?["axis"] as? String else { return nil }
        return name == "column" ? .column : .row
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let axis = axis(of: event) else {
            super.cursorUpdate(with: event)
            return
        }
        NSCursor._setOverrideCursor(cursor(for: axis))
    }

    override func mouseEntered(with event: NSEvent) {
        guard let axis = axis(of: event) else { return }
        hoveredAxis = axis
        NSCursor._setOverrideCursor(cursor(for: axis))
    }

    override func mouseExited(with event: NSEvent) {
        guard let axis = axis(of: event), hoveredAxis == axis else { return }
        hoveredAxis = nil
        if activeDrag == nil {
            NSCursor._clearOverrideCursorAndSetArrow()
        }
    }

    private func cursor(for axis: PaneDivider.Axis) -> NSCursor {
        axis == .column ? .resizeLeftRight : .resizeUpDown
    }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return grips.contains { $0.frame.contains(local) } ? self : nil
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let grip = grips.first(where: { $0.frame.contains(location) }) else { return }
        activeDrag = grip.axis
        NSCursor._setOverrideCursor(cursor(for: grip.axis))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let axis = activeDrag else { return }
        let location = convert(event.locationInWindow, from: nil)
        NSCursor._setOverrideCursor(cursor(for: axis))
        onDrag?(axis, axis == .column ? location.x : location.y)
    }

    override func mouseUp(with _: NSEvent) {
        guard let axis = activeDrag else { return }
        activeDrag = nil
        onDragEnded?(axis)
        if hoveredAxis == nil {
            NSCursor._clearOverrideCursorAndSetArrow()
        }
    }
}
