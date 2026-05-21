import AppKit
import SwiftUI

/// Resigns first responder when clicking outside of text fields.
///
/// This provides standard "click outside to dismiss" behavior for text fields,
/// matching web and native platform conventions. When the user clicks anywhere
/// outside the currently focused text field, it loses focus.
///
/// ## Usage
///
/// Apply as an overlay on a container view:
///
/// ```swift
/// SidebarContent()
///     .overlay {
///         ClickOutsideTextFieldHandler()
///     }
/// ```
///
/// ## Behavior
///
/// - Only triggers when a text field has focus
/// - Ignores clicks inside text fields (lets them handle focus normally)
/// - Does not consume the event (other handlers still receive it)
struct ClickOutsideTextFieldHandler: NSViewRepresentable {
    func makeNSView(context _: Context) -> ClickOutsideHandlerView {
        ClickOutsideHandlerView()
    }

    func updateNSView(_: ClickOutsideHandlerView, context _: Context) {}
}

/// NSView that monitors clicks and resigns text field focus when clicking outside.
///
/// ## Implementation Notes
///
/// We use `makeFirstResponder(contentView)` to end editing because:
///
/// - Calling `makeFirstResponder(_:)` synchronously causes a priority inversion warning.
///   The event monitor runs at user-interactive QoS, and `makeFirstResponder` internally
///   waits on lower-priority work.
///
/// - `endEditing(for:)` doesn't properly trigger SwiftUI's `@FocusState` updates,
///   leaving the text field visually focused even though editing ended.
///
/// - We use `DispatchQueue.main.async` to defer `makeFirstResponder(contentView)` to the
///   next runloop iteration. This lets the event monitor return immediately (avoiding
///   priority inversion) while still properly updating SwiftUI state.
final class ClickOutsideHandlerView: NSView {
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    // Don't intercept hit testing - let events pass through
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            setupEventMonitor()
        } else {
            removeEventMonitor()
        }
    }

    override func removeFromSuperview() {
        removeEventMonitor()
        super.removeFromSuperview()
    }

    private func setupEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleLeftClick(event)
            // Always return the event - we don't consume it, just observe
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleLeftClick(_ event: NSEvent) {
        guard let window,
              let firstResponder = window.firstResponder as? NSTextView,
              firstResponder.delegate is NSTextField else {
            return
        }

        // Get the clicked view
        let locationInWindow = event.locationInWindow
        guard let contentView = window.contentView,
              let clickedView = contentView.hitTest(locationInWindow) else {
            return
        }

        // Check if click is inside a text field
        if isInsideTextField(clickedView) {
            return
        }

        // Click is outside text field - transfer focus to end editing.
        // Dispatch async to avoid priority inversion: the event monitor runs at
        // user-interactive QoS, and makeFirstResponder internally waits on
        // lower-priority work. Deferring to the next runloop iteration lets
        // the monitor return immediately while still triggering @FocusState updates.
        DispatchQueue.main.async { [weak window, weak contentView] in
            guard let window, let contentView else { return }
            // Re-check that a text field is still first responder.
            // State may have changed between event capture and async execution.
            guard let currentResponder = window.firstResponder as? NSTextView,
                  currentResponder.delegate is NSTextField else {
                return
            }
            window.makeFirstResponder(contentView)
        }
    }

    /// Checks if a view is inside a text field (including the field editor).
    private func isInsideTextField(_ view: NSView) -> Bool {
        var current: NSView? = view

        while let v = current {
            if v is NSTextField {
                return true
            }
            // NSTextView used as field editor
            if let textView = v as? NSTextView,
               textView.delegate is NSTextField {
                return true
            }
            current = v.superview
        }

        return false
    }
}
