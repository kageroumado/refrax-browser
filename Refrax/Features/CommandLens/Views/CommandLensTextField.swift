import AppKit
import SwiftUI

// MARK: - Custom NSTextField

/// Custom NSTextField that intercepts arrow key events and forwards them to a handler.
///
/// NSTextField's field editor normally handles arrow keys for cursor movement, which means
/// `control(_:textView:doCommandBy:)` isn't called. This subclass overrides `keyDown` to
/// intercept arrow keys before they reach the field editor.
final class CommandLensNSTextField: NSTextField {
    var onArrowKey: ((NSEvent.SpecialKey) -> Bool)?

    override func keyDown(with event: NSEvent) {
        // Check for arrow keys
        if let specialKey = event.specialKey {
            switch specialKey {
            case .upArrow, .downArrow, .leftArrow, .rightArrow:
                if onArrowKey?(specialKey) == true {
                    return // Event was handled
                }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}

// MARK: - SwiftUI Representable

/// Custom text field with Arc-style inline completion
/// Integrated to match the exact styling of SwiftUI TextField
struct CommandLensTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat

    // Inline completion
    let inlineCompletion: String?
    let inlineCompletionRange: NSRange?

    /// Binding to trigger select all. Set to `true` to select all text, resets to `false` after selection.
    @Binding var selectAll: Bool

    // Callbacks
    let onTextChange: (String) -> Void
    let onCommit: (_ commandKeyHeld: Bool, _ optionKeyHeld: Bool) -> Void
    let onTab: () -> Void
    let onEscape: () -> Void
    let onUpArrow: () -> Void
    let onDownArrow: () -> Void
    let onLeftArrow: () -> Bool // Returns true if handled (e.g., empty state action)
    let onRightArrow: () -> Bool // Returns true if handled (e.g., empty state action)
    let onDelete: () -> Bool
    let onAcceptCompletion: () -> Void
    let onRejectCompletion: () -> Void

    func makeNSView(context: Context) -> CommandLensNSTextField {
        let textField = CommandLensNSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: fontSize)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.alignment = .left
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail

        // Set up arrow key handler
        textField.onArrowKey = { [weak coordinator = context.coordinator] specialKey in
            coordinator?.handleArrowKey(specialKey) ?? false
        }

        // Make it become first responder and lock focus to prevent theft during app switching
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            (textField.window as? RefraxWindow)?.lockedFirstResponder = textField
        }

        // Retry after a short delay to handle cases where the window is still
        // settling focus (e.g., rapid app switch followed by keyboard shortcut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak textField] in
            guard let textField, textField.currentEditor() == nil else { return }
            textField.window?.makeFirstResponder(textField)
            (textField.window as? RefraxWindow)?.lockedFirstResponder = textField
        }

        return textField
    }
    
    func updateNSView(_ nsView: CommandLensNSTextField, context: Context) {
        // Update arrow key handler reference (coordinator might have changed)
        nsView.onArrowKey = { [weak coordinator = context.coordinator] specialKey in
            coordinator?.handleArrowKey(specialKey) ?? false
        }
        // Update placeholder
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        // Update font size
        if nsView.font?.pointSize != fontSize {
            nsView.font = .systemFont(ofSize: fontSize)
        }

        // Get current editor and selection
        let editor = nsView.currentEditor()
        let savedSelection = editor?.selectedRange

        // Update text if it changed externally (but not if we're just updating the completion)
        if nsView.stringValue != text, inlineCompletion == nil {
            nsView.stringValue = text

            // Restore cursor position if we're not at the end
            if let range = savedSelection, range.location < text.count {
                editor?.selectedRange = range
            }
        }

        // Handle select all trigger
        if selectAll {
            DispatchQueue.main.async {
                nsView.currentEditor()?.selectAll(nil)
                selectAll = false
            }
        }

        // Apply inline completion with selection.
        // Skip if the user has edited the field but the binding hasn't caught up yet —
        // otherwise we'd overwrite their edit with the stale completion.
        if let completion = inlineCompletion,
           let range = inlineCompletionRange,
           !context.coordinator.hasPendingTextChange {
            // Only update if the base text matches
            if text.count <= completion.count,
               completion.lowercased().hasPrefix(text.lowercased()) {
                // Set the full completion text
                nsView.stringValue = completion

                // Select the completion part
                if let editor {
                    editor.selectedRange = range
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onTextChange: onTextChange,
            onCommit: onCommit,
            onTab: onTab,
            onEscape: onEscape,
            onUpArrow: onUpArrow,
            onDownArrow: onDownArrow,
            onLeftArrow: onLeftArrow,
            onRightArrow: onRightArrow,
            onDelete: onDelete,
            onAcceptCompletion: onAcceptCompletion,
            onRejectCompletion: onRejectCompletion,
        )
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onTextChange: (String) -> Void
        let onCommit: (_ commandKeyHeld: Bool, _ optionKeyHeld: Bool) -> Void
        let onTab: () -> Void
        let onEscape: () -> Void
        let onUpArrow: () -> Void
        let onDownArrow: () -> Void
        let onLeftArrow: () -> Bool
        let onRightArrow: () -> Bool
        let onDelete: () -> Bool
        let onAcceptCompletion: () -> Void
        let onRejectCompletion: () -> Void

        private var isUpdatingFromCompletion = false
        private var isManuallyDeleting = false
        /// Set when controlTextDidChange fires, cleared after the deferred binding update runs.
        /// Prevents updateNSView from overwriting user edits with stale completion state.
        var hasPendingTextChange = false

        /// Maximum character limit for input (matches typical browser address bar limits).
        private static let maxCharacterCount = 2_000

        init(
            text: Binding<String>,
            onTextChange: @escaping (String) -> Void,
            onCommit: @escaping (_ commandKeyHeld: Bool, _ optionKeyHeld: Bool) -> Void,
            onTab: @escaping () -> Void,
            onEscape: @escaping () -> Void,
            onUpArrow: @escaping () -> Void,
            onDownArrow: @escaping () -> Void,
            onLeftArrow: @escaping () -> Bool,
            onRightArrow: @escaping () -> Bool,
            onDelete: @escaping () -> Bool,
            onAcceptCompletion: @escaping () -> Void,
            onRejectCompletion: @escaping () -> Void,
        ) {
            self._text = text
            self.onTextChange = onTextChange
            self.onCommit = onCommit
            self.onTab = onTab
            self.onEscape = onEscape
            self.onUpArrow = onUpArrow
            self.onDownArrow = onDownArrow
            self.onLeftArrow = onLeftArrow
            self.onRightArrow = onRightArrow
            self.onDelete = onDelete
            self.onAcceptCompletion = onAcceptCompletion
            self.onRejectCompletion = onRejectCompletion
        }

        /// Handles arrow key events from the custom NSTextField.
        ///
        /// Called from keyDown before the event reaches the field editor.
        /// Returns true if the event was handled and should not propagate.
        func handleArrowKey(_ key: NSEvent.SpecialKey) -> Bool {
            switch key {
            case .upArrow:
                onUpArrow()
                return true

            case .downArrow:
                onDownArrow()
                return true

            case .leftArrow:
                // Only handle left arrow when input is empty (for empty state action)
                if text.isEmpty {
                    return onLeftArrow()
                }
                return false // Let the text field handle cursor movement

            case .rightArrow:
                // Only handle right arrow when input is empty (for empty state action)
                // or when we need to accept inline completion
                if text.isEmpty {
                    return onRightArrow()
                }
                // For non-empty text, accept completion is handled by the delegate method
                return false

            default:
                return false
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }

            // If we're updating from a completion acceptance, don't reject
            if isUpdatingFromCompletion {
                isUpdatingFromCompletion = false
                return
            }

            // Block updateNSView from overwriting user edits until the deferred binding update runs
            hasPendingTextChange = true

            // Sanitize input: replace newlines with spaces, enforce character limit
            var newValue = textField.stringValue
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            // Truncate if exceeds maximum length
            if newValue.count > Self.maxCharacterCount {
                newValue = String(newValue.prefix(Self.maxCharacterCount))
            }

            // Update text field if sanitization changed the value
            if textField.stringValue != newValue {
                textField.stringValue = newValue
            }

            // If we're manually deleting, skip the normal rejection logic
            if isManuallyDeleting {
                isManuallyDeleting = false
                // Defer SwiftUI state mutations to next runloop
                DispatchQueue.main.async {
                    self.text = newValue
                    self.onTextChange(newValue)
                    self.hasPendingTextChange = false
                }
                return
            }

            // Capture current text for comparison (before deferring)
            let currentText = text

            // Defer SwiftUI state mutations to next runloop
            DispatchQueue.main.async {
                // If the user deleted text or typed new characters, reject completion
                if newValue.count < currentText.count || !newValue.hasPrefix(currentText) {
                    self.onRejectCompletion()
                }

                // Update binding
                self.text = newValue

                // Trigger new completion calculation
                self.onTextChange(newValue)
                self.hasPendingTextChange = false
            }
        }
        
        func control(_: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // Enter key (with or without Option) - check modifier keys
                // Option+Enter triggers insertNewlineIgnoringFieldEditor, so we handle both
                let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                let commandKeyHeld = modifiers.contains(.command)
                let optionKeyHeld = modifiers.contains(.option)
                onCommit(commandKeyHeld, optionKeyHeld)
                return true
                
            case #selector(NSResponder.cancelOperation(_:)):
                // Escape key
                onEscape()
                return true
                
            case #selector(NSResponder.insertTab(_:)):
                // Tab key
                onTab()
                return true
                
            case #selector(NSResponder.moveUp(_:)):
                // Up arrow
                onUpArrow()
                return true
                
            case #selector(NSResponder.moveDown(_:)):
                // Down arrow
                onDownArrow()
                return true
                
            case #selector(NSResponder.moveLeft(_:)):
                // Left arrow - check if empty state action should handle it
                let selectedRange = textView.selectedRange
                let isAtStart = selectedRange.location == 0 && selectedRange.length == 0

                if isAtStart, onLeftArrow() {
                    return true
                }
                return false

            case #selector(NSResponder.moveRight(_:)):
                // Right arrow at end of text - either accept completion or trigger empty state
                let selectedRange = textView.selectedRange
                let hasSelection = selectedRange.length > 0
                let isAtEnd = selectedRange.location + selectedRange.length >= textView.string.count

                // If there's a selection, let default behavior collapse it to the right
                if hasSelection {
                    return false
                }

                if isAtEnd {
                    // First try to handle as empty state action (when input is empty)
                    if onRightArrow() {
                        return true
                    }
                    // Otherwise accept inline completion
                    isUpdatingFromCompletion = true
                    onAcceptCompletion()
                    return true
                }
                return false
                
            case #selector(NSResponder.deleteBackward(_:)):
                // Backspace
                let selectedRange = textView.selectedRange
                
                // If there's a selection, delete it manually
                if selectedRange.length > 0 {
                    // Set flag to prevent double-processing
                    isManuallyDeleting = true
                    
                    // Delete the selected text
                    if textView.shouldChangeText(in: selectedRange, replacementString: "") {
                        textView.replaceCharacters(in: selectedRange, with: "")
                        textView.didChangeText()
                        // controlTextDidChange will be called automatically, which will:
                        // - Update the binding
                        // - Call onTextChange
                        // - Skip onRejectCompletion due to isManuallyDeleting flag
                    }
                    
                    // Now reject the completion
                    onRejectCompletion()
                    return true
                }
                
                // For cursor-only position, let the delete handler decide
                if onDelete() {
                    return true
                }
                
                // Always reject completion on backspace
                onRejectCompletion()
                return false
                
            default:
                return false
            }
        }
    }
}
