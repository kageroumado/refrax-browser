import AppKit
import SwiftUI

struct TabDraggableRepresentable: NSViewRepresentable {
    let tab: Tab
    let onDetach: (Tab, NSPoint) -> Void

    func makeNSView(context _: Context) -> NSView {
        DraggableTabView(tab: tab, onDetach: onDetach)
    }

    func updateNSView(_: NSView, context _: Context) {}
}

final class DraggableTabView: NSView {
    let tab: Tab
    let onDetach: (Tab, NSPoint) -> Void
    private var mouseDownLocation: NSPoint?

    init(tab: Tab, onDetach: @escaping (Tab, NSPoint) -> Void) {
        self.tab = tab
        self.onDetach = onDetach
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        if distance > 5 { // threshold to start drag
            beginDraggingSession(with: event)
            mouseDownLocation = nil
        }
    }

    private func beginDraggingSession(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(tab.id.uuidString, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: snapshot())

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    private func snapshot() -> NSImage {
        let rep = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

extension DraggableTabView: NSDraggingSource {
    func draggingSession(_: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation == .delete {
            onDetach(tab, screenPoint)
        }
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .move
    }
}
