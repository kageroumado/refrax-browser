import AppKit
import SwiftUI

/// Keeps the webpage interactive between the floating cards.
final class FloatingTabsHostingView<Content: View>: NSHostingView<Content> {
    var hitRegions: () -> [CGRect] = { [] }
    var onPointerDown: ((CGPoint) -> Void)?
    /// A right-click at a point; returns whether it was handled, which keeps it from the page.
    var onSecondaryPointerDown: ((CGPoint, NSEvent) -> Bool)?
    var controlState: (() -> ControlIslandState?)?
    private var pointerMonitor: Any?
    private var pointerTrackingArea: NSTrackingArea?

    // The pointer's travel reaches the controls through a tracking area, so a rail hidden at
    // the window's edge comes back whichever app is active, and the pointer's exit past that
    // edge counts as reaching it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        controlState?()?.pointerMoved?(topLeadingPoint(convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        controlState?()?.pointerMoved?(topLeadingPoint(convert(event.locationInWindow, from: nil)))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        pointerMonitor = nil
        guard window != nil else { return }
        window?.acceptsMouseMovedEvents = true
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self, event.window === window else { return event }
            let point = topLeadingPoint(convert(event.locationInWindow, from: nil))
            if event.type == .leftMouseDown {
                onPointerDown?(point)
            }
            if event.type == .rightMouseDown, onSecondaryPointerDown?(point, event) == true {
                return nil
            }
            guard let state = controlState?(),
                  !state.isPresenting, !state.hitRegions.isEmpty else { return event }
            state.dismissIfOutside(point)
            return event
        }
    }

    isolated deinit {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
    }

    private func topLeadingPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = topLeadingPoint(convert(point, from: superview))
        guard hitRegions().contains(where: { $0.contains(local) }) else { return nil }
        return super.hitTest(point)
    }
}
