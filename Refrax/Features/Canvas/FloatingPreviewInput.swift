import AppKit

/// Consumes the reveal modifier while preserving native webpage input and scroll phases.
enum FloatingPreviewInput {
    static func removingRevealModifier(from event: NSEvent, key: FloatingRevealKey = .current) -> NSEvent {
        guard event.modifierFlags.contains(key.flag) else { return event }
        if event.type == .keyDown || event.type == .keyUp {
            return NSEvent.keyEvent(
                with: event.type, location: event.locationInWindow,
                modifierFlags: event.modifierFlags.subtracting(key.flag),
                timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                characters: event.charactersIgnoringModifiers ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat, keyCode: event.keyCode
            ) ?? event
        }
        guard let copy = event.cgEvent?.copy() else { return event }
        copy.flags.remove(key.cgFlag)
        return NSEvent(cgEvent: copy) ?? event
    }
}
