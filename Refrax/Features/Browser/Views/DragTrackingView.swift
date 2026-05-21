import AppKit
import SwiftUI

/// Result of validating a drag operation
enum DragValidationResult {
    /// The drag is valid and can be dropped
    case valid
    /// The drag is invalid with a reason message
    case invalid(message: String)
    /// No target found (not over a valid drop zone)
    case noTarget
}

/// NSView-based drag tracker using NSDraggingDestination protocol
///
/// This view tracks drag operations from the sidebar and allows dropping tabs into empty layout slots.
/// It uses AppKit's native drag-and-drop infrastructure for reliable cross-view drag handling.
struct DragTrackingView: NSViewRepresentable {
    let onDragMove: (CGPoint, NSPasteboard) -> DragValidationResult
    let onDragExit: () -> Void
    let onDrop: (NSPasteboard, CGPoint) -> Bool

    func makeNSView(context _: Context) -> DragTrackingNSView {
        let view = DragTrackingNSView()
        view.onDragMove = onDragMove
        view.onDragExit = onDragExit
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DragTrackingNSView, context _: Context) {
        nsView.onDragMove = onDragMove
        nsView.onDragExit = onDragExit
        nsView.onDrop = onDrop
    }
}

/// The underlying NSView that implements NSDraggingDestination for drop handling
final class DragTrackingNSView: NSView {
    var onDragMove: ((CGPoint, NSPasteboard) -> DragValidationResult)?
    var onDragExit: (() -> Void)?
    var onDrop: ((NSPasteboard, CGPoint) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([DragPasteboardType.refraxTabID, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([DragPasteboardType.refraxTabID, .string])
    }

    /// Allow mouse events to pass through to views beneath this drag tracking overlay.
    ///
    /// This view only needs to intercept drag-and-drop operations, not regular clicks.
    /// Returning nil for non-drag events lets the empty slot views receive tap gestures.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        let result = onDragMove?(flippedLocation, sender.draggingPasteboard)

        switch result {
        case .valid:
            return .copy
        case .invalid:
            return []
        case .noTarget, .none:
            return .copy
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        let result = onDragMove?(flippedLocation, sender.draggingPasteboard)

        switch result {
        case .valid:
            return .copy
        case .invalid:
            return []
        case .noTarget, .none:
            return .copy
        }
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        onDragExit?()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let location = convert(sender.draggingLocation, from: nil)
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        return onDrop?(sender.draggingPasteboard, flippedLocation) ?? false
    }
}
