import AppKit
import SwiftUI

/// An inline island name editor that claims its native field editor after mounting.
struct IslandNameField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> IslandNameTextField {
        let field = IslandNameTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.font = .systemFont(ofSize: fontSize)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.setAccessibilityLabel("Name")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: IslandNameTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: IslandNameTextField, coordinator _: Coordinator) {
        field.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IslandNameField

        init(parent: IslandNameField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_: Notification) { parent.onCommit() }

        func control(_: NSControl, textView _: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}

final class IslandNameTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeKey()
            // AppKit selects the text during this transition. Selecting again ends the edit.
            window.makeFirstResponder(self)
        }
    }

    override func setAccessibilityValue(_ value: Any?) {
        let previous = stringValue
        super.setAccessibilityValue(value)
        guard stringValue != previous else { return }
        delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: self))
    }
}
