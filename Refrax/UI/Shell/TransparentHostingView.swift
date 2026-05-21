import AppKit
import SwiftUI

/// Hosting view for overlays that conditionally passes through events.
///
/// When `shouldPassThrough()` returns true, both hit tests and cursor updates
/// pass through to views underneath (e.g., WebKit). When false, this view
/// captures hits and forces the cursor to arrow, preventing WebKit from
/// changing the cursor to link/text selection cursors.
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    let shouldPassThrough: () -> Bool
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
        if shouldPassThrough() {
            return nil
        }
        return super.hitTest(point)
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
        if !shouldPassThrough() {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
}
