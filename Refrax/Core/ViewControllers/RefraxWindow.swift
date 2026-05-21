import AppKit

final class RefraxWindow: NSWindow {
    /// The responder that should retain first responder status.
    ///
    /// When set, `makeFirstResponder(_:)` rejects attempts to change focus away from
    /// this view (or its field editor). This prevents focus theft during app switching,
    /// which otherwise causes the Command Lens text field to lose keyboard input.
    ///
    /// Modeled after Safari's `LockableFirstResponder` pattern, which uses the same
    /// approach for their address bar.
    weak var lockedFirstResponder: NSView?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        toolbarStyle = .unified
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear

        // Set restoration identifier to enable state restoration
        identifier = NSUserInterfaceItemIdentifier("RefraxWindow")
        isRestorable = true
        restorationClass = RefraxWindowRestoration.self
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        guard lockedFirstResponder != nil else {
            return super.makeFirstResponder(responder)
        }

        // Allow the locked view itself
        if responder === lockedFirstResponder {
            return super.makeFirstResponder(responder)
        }

        // Allow field editors — NSTextField swaps in a shared NSTextView as the
        // actual first responder during editing. Blocking this would break typing.
        if let textView = responder as? NSTextView, textView.isFieldEditor {
            return super.makeFirstResponder(responder)
        }

        return false
    }

    override func becomeKey() {
        super.becomeKey()

        // Proactively restore focus to the locked responder on app-switch return.
        // The override above prevents stealing, but macOS may have already changed
        // the first responder during deactivation/reactivation before our override
        // gets a chance to block it.
        if let locked = lockedFirstResponder {
            _ = makeFirstResponder(locked)
        }
    }
}
