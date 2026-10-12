import AppKit
import SwiftUI

/// The movement available beneath the pointer, including an in-progress gesture.
nonisolated enum ControlIslandDragFeedback: Equatable {
    case idle
    case ready(ControlIslandDragTarget)
    case dragging(ControlIslandDragTarget)
    case unavailable

}

/// Reserves Option-drag before either native widgets or SwiftUI buttons receive a press.
struct ControlIslandOptionDrag: NSViewRepresentable {
    let target: ControlIslandDragTarget
    var isEnabled = true
    var cornerRadius: CGFloat = ControlIslandPlacement.cornerRadius
    let onFeedback: (ControlIslandDragFeedback) -> Void
    let onBegin: () -> Void
    let onMove: (CGSize) -> Void
    let onEnd: () -> Void

    func makeNSView(context _: Context) -> ControlIslandOptionDragView {
        ControlIslandOptionDragView()
    }

    func updateNSView(_ view: ControlIslandOptionDragView, context _: Context) {
        view.isEnabled = isEnabled
        view.target = target
        view.cornerRadius = cornerRadius
        view.onFeedback = onFeedback
        view.onBegin = onBegin
        view.onMove = onMove
        view.onEnd = onEnd
    }

    static func dismantleNSView(_ view: ControlIslandOptionDragView, coordinator _: ()) {
        view.finish()
    }
}

final class ControlIslandOptionDragView: NSView {
    var target: ControlIslandDragTarget = .panel
    var isEnabled = true {
        didSet { if !isEnabled { finish() } }
    }
    var cornerRadius: CGFloat = 0
    var onFeedback: (ControlIslandDragFeedback) -> Void = { _ in }
    var onBegin: () -> Void = {}
    var onMove: (CGSize) -> Void = { _ in }
    var onEnd: () -> Void = {}
    private(set) var feedback: ControlIslandDragFeedback = .idle
    private var monitor: Any?
    private var tracking: NSTrackingArea?
    private var cursorIsPushed = false
    private var cursorRefreshQueued = false
    private var origin: CGPoint?
    private var hasMoved = false
    private var draggedTarget: ControlIslandDragTarget = .panel
    private static let threshold: CGFloat = 3
    private lazy var activityObserver = WindowActivityObserver { [weak self] active in
        if !active { self?.finish() }
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        finish()
        activityObserver.observe(window)
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown,
            .flagsChanged, .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
        ]) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        let rect = bounds.intersection(visibleRect)
        guard !rect.isEmpty else { return }
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow], owner: self)
        tracking = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { refreshFeedback(for: event) }
    override func mouseExited(with event: NSEvent) { refreshFeedback(for: event) }
    override func cursorUpdate(with event: NSEvent) { refreshFeedback(for: event) }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if cursorIsPushed { NSCursor.pop() }
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        if let origin {
            if event.type == .keyDown, event.keyCode == 53 {
                finish()
                return nil
            }
            if event.type == .leftMouseUp {
                finish()
                refreshFeedback(for: event)
                return nil
            }
            if event.type == .leftMouseDragged {
                let point = window.convertPoint(toScreen: event.locationInWindow)
                let translation = CGSize(width: point.x - origin.x, height: origin.y - point.y)
                if draggedTarget == .panel, hasMoved || hypot(translation.width, translation.height) >= Self.threshold {
                    hasMoved = true
                    onMove(translation)
                }
                applyCursor()
                return nil
            }
            applyCursor()
            return event
        }
        refreshFeedback(for: event)
        guard event.type == .leftMouseDown, event.window === window,
              event.modifierFlags.contains(.option), containsPointer(at: event.locationInWindow) else { return event }

        origin = window.convertPoint(toScreen: event.locationInWindow)
        draggedTarget = target
        setFeedback(canMoveTarget ? .dragging(target) : .unavailable)
        onBegin()
        if target == .window, canMoveTarget {
            window.performDrag(with: event)
            finish()
            refreshFeedback(at: window.mouseLocationOutsideOfEventStream, modifiers: NSEvent.modifierFlags)
        }
        return nil
    }

    func finish() {
        let wasDragging = origin != nil
        origin = nil
        hasMoved = false
        setFeedback(.idle)
        if wasDragging { onEnd() }
    }

    private var canMoveTarget: Bool {
        target == .panel || (window?.isMovable == true && window?.styleMask.contains(.fullScreen) == false)
    }

    private func containsPointer(at windowPoint: CGPoint) -> Bool {
        guard isEnabled, window?.attachedSheet == nil, !isHiddenOrHasHiddenAncestor else { return false }
        let point = convert(windowPoint, from: nil)
        return bounds.intersection(visibleRect).contains(point)
            && NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).contains(point)
    }

    private func refreshFeedback(for event: NSEvent) {
        guard origin == nil else { applyCursor(); return }
        guard let window, event.window === window else { setFeedback(.idle); return }
        let point = event.type == .flagsChanged ? window.mouseLocationOutsideOfEventStream : event.locationInWindow
        refreshFeedback(at: point, modifiers: event.modifierFlags)
    }

    private func refreshFeedback(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        let ready = modifiers.contains(.option) && containsPointer(at: point)
        setFeedback(ready ? (canMoveTarget ? .ready(target) : .unavailable) : .idle)
    }

    private func setFeedback(_ value: ControlIslandDragFeedback) {
        if feedback != value {
            feedback = value
            if cursorIsPushed { NSCursor.pop(); cursorIsPushed = false }
            if let cursor { cursor.push(); cursorIsPushed = true }
            onFeedback(value)
        }
        applyCursor()
    }

    private var cursor: NSCursor? {
        switch feedback {
        case .idle: nil
        case .ready: .openHand
        case .dragging: .closedHand
        case .unavailable: .operationNotAllowed
        }
    }

    /// Reapplies the gesture cursor after AppKit dispatches native widget tracking.
    private func applyCursor() {
        guard let cursor else { return }
        cursor.set()
        guard !cursorRefreshQueued else { return }
        cursorRefreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            cursorRefreshQueued = false
            self.cursor?.set()
        }
    }
}
