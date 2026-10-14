import AppKit
import SwiftUI

/// Hosting view for overlays that conditionally passes through events.
///
/// When `shouldPassThrough()` returns true, both hit tests and cursor updates
/// pass through to views underneath (e.g., WebKit). When false, this view
/// captures hits and forces the cursor to arrow, preventing WebKit from
/// changing the cursor to link/text selection cursors. Points inside
/// `passThroughRegions()` (top-left window content coordinates) pass through
/// regardless, so an overlay can leave openings for the content it points at. While
/// `capturedRegions()` returns regions, only points inside them reach the overlay.
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    let shouldPassThrough: () -> Bool
    var passThroughRegions: () -> [CGRect] = { [] }
    var capturedRegions: () -> [CGRect]? = { nil }
    private var trackingArea: NSTrackingArea?

    init(rootView: Content, shouldPassThrough: @escaping () -> Bool) {
        self.shouldPassThrough = shouldPassThrough
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @preconcurrency
    dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @preconcurrency
    required init(rootView _: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if shouldPassThrough() || isInPassThroughRegion(convert(point, from: superview)) {
            return nil
        }
        return super.hitTest(point)
    }

    private func isInPassThroughRegion(_ local: NSPoint) -> Bool {
        let topLeading = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        if let captured = capturedRegions(), !captured.contains(where: { $0.contains(topLeading) }) {
            return true
        }
        return passThroughRegions().contains { $0.contains(topLeading) }
    }

    // MARK: - Cursor Blocking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil,
        )

        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !shouldPassThrough() {
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !shouldPassThrough(), !isInPassThroughRegion(convert(event.locationInWindow, from: nil)) {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
}
