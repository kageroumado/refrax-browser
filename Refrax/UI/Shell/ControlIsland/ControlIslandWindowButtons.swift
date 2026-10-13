import AppKit
import SwiftUI

/// AppKit's window widgets, with their native artwork centered in full-row targets.
struct ControlIslandWindowButtons: NSViewRepresentable {
    func makeNSView(context _: Context) -> ControlIslandWindowButtonGroup {
        ControlIslandWindowButtonGroup()
    }

    func updateNSView(_ view: ControlIslandWindowButtonGroup, context _: Context) {
        view.updateAccessibilityLabels()
    }

    static func dismantleNSView(_ view: ControlIslandWindowButtonGroup, coordinator _: ()) {
        view.setRollover(false)
    }
}

final class ControlIslandWindowButtonGroup: NSView {
    private static let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private(set) var buttons: [NSButton] = []
    private var groupTrackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var rolloverRefreshScheduled = false
    private var pointerMonitor: Any?
    private lazy var activityObserver = WindowActivityObserver { [weak self] _ in
        self?.refreshRolloverFromPointer()
    }

    override var isFlipped: Bool {
        true
    }

    init() {
        super.init(frame: .zero)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        for kind in Self.kinds {
            guard let button = NSWindow.standardWindowButton(kind, for: style) else { continue }
            button.tag = Int(kind.rawValue)
            button.focusRingType = .none
            button.target = self
            button.action = #selector(performWindowAction(_:))
            addSubview(button)
            buttons.append(button)
        }
        updateAccessibilityLabels()
        setAccessibilityElement(false)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        for (index, button) in buttons.enumerated() {
            let frame = CGRect(
                x: 0,
                y: CGFloat(index) * ControlIslandPlacement.rowHeight,
                width: bounds.width,
                height: ControlIslandPlacement.rowHeight,
            )
            if button.frame != frame {
                button.frame = frame
            }
        }
        refreshRolloverFromPointer()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let groupTrackingArea {
            removeTrackingArea(groupTrackingArea)
        }
        groupTrackingArea = nil
        let rect = bounds.intersection(visibleRect)
        guard !rect.isEmpty else {
            refreshRolloverFromPointer()
            return
        }
        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
        )
        addTrackingArea(area)
        groupTrackingArea = area
        refreshRolloverFromPointer()
    }

    override func mouseEntered(with event: NSEvent) {
        updateRollover(at: event.locationInWindow)
    }
    override func mouseMoved(with event: NSEvent) {
        updateRollover(at: event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) {
        updateRollover(at: event.locationInWindow)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        pointerMonitor = nil
        isPointerInside = false
        setRollover(false)
        activityObserver.observe(nil)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAccessibilityLabels()
        activityObserver.observe(window)
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .mouseEntered, .mouseExited]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.window {
                updateRollover(at: event.locationInWindow)
            } else if isPointerInside {
                isPointerInside = false
                setRollover(false)
            }
            return event
        }
    }

    isolated deinit {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
    }

    private func refreshRolloverFromPointer() {
        guard let window else { return }
        updateRollover(at: window.mouseLocationOutsideOfEventStream)
    }

    private func updateRollover(at point: CGPoint) {
        let local = convert(point, from: nil)
        let inside = !isHiddenOrHasHiddenAncestor && window?.attachedSheet == nil
            && bounds.contains(local) && visibleRect.contains(local)
        guard inside || isPointerInside else { return }
        isPointerInside = inside
        setRollover(isPointerInside)
        scheduleRolloverRefresh()
    }

    /// NSThemeFrame clears its auxiliary hover bit while rebuilding tracking areas.
    /// Apply the group's pointer state after AppKit completes that event's tracking work.
    private func scheduleRolloverRefresh() {
        guard !rolloverRefreshScheduled else { return }
        rolloverRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            rolloverRefreshScheduled = false
            setRollover(isPointerInside)
        }
    }

    func updateAccessibilityLabels() {
        for button in buttons {
            let title: String = switch NSWindow.ButtonType(rawValue: UInt(button.tag)) {
            case .closeButton: "Close window"
            case .miniaturizeButton: "Minimize window"
            default: window?.styleMask.contains(.fullScreen) == true ? "Exit full screen" : "Full screen"
            }
            button.setAccessibilityLabel(title)
            button.toolTip = title
        }
    }

    /// Factory widgets read the theme frame's auxiliary group hover bit.
    /// AppKit owns their glyph shape, compositing, inactive appearance, and full-screen state.
    func setRollover(_ entered: Bool) {
        guard let theme = window?.contentView?.superview else { return }
        let selector = NSSelectorFromString("_setMouseEnteredGroup:entered:")
        guard theme.responds(to: selector), let implementation = theme.method(for: selector) else { return }
        typealias SetGroup = @convention(c) (AnyObject, Selector, Bool, Bool) -> Void
        unsafeBitCast(implementation, to: SetGroup.self)(theme, selector, false, entered)
        let refresh = NSSelectorFromString("mouseEnteredOrExited")
        for button in buttons where button.responds(to: refresh) {
            button.perform(refresh)
        }
    }

    @objc
    private func performWindowAction(_ sender: NSButton) {
        switch NSWindow.ButtonType(rawValue: UInt(sender.tag)) {
        case .closeButton: window?.performClose(sender)
        case .miniaturizeButton: window?.miniaturize(sender)
        default: window?.toggleFullScreen(sender)
        }
    }
}
