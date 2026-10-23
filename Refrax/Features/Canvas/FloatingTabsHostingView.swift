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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        pointerMonitor = nil
        guard window != nil else { return }
        window?.acceptsMouseMovedEvents = true
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self, event.window === window else { return event }
            let point = topLeadingPoint(convert(event.locationInWindow, from: nil))
            if event.type == .mouseMoved {
                controlState?()?.pointerMoved?(point)
                return event
            }
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
