import AppKit
import SwiftUI

/// Hosts the File Island over the page: it takes clicks only on the island and follows the
/// pointer so the island can rest and wake.
final class FileIslandHostingView<Content: View>: NSHostingView<Content> {
    var state: (() -> FileIslandState?)?
    private var pointerMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        pointerMonitor = nil
        guard window != nil else { return }
        window?.acceptsMouseMovedEvents = true
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self, event.window === window, let state = state?(), !state.hitRegions.isEmpty else { return event }
            state.tracksPointer(topLeadingPoint(convert(event.locationInWindow, from: nil)))
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
        guard state?()?.hitRegions.contains(where: { $0.contains(local) }) == true else { return nil }
        return super.hitTest(point)
    }
}
