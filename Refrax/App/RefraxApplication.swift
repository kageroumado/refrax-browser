import AppKit

/// Refrax's application object.
///
/// Adopts Chromium's application protocol so the Chromium engine plug-in can run
/// in this process: Chromium's main-thread message pump asks whether
/// `-sendEvent:` is on the stack before it runs nested work.
final class RefraxApplication: NSApplication, CefAppProtocol {
    private var handlingSendEvent = false

    func isHandlingSendEvent() -> Bool {
        handlingSendEvent
    }

    func setHandlingSendEvent(_ handlingSendEvent: Bool) {
        self.handlingSendEvent = handlingSendEvent
    }

    override func sendEvent(_ event: NSEvent) {
        let previous = handlingSendEvent
        handlingSendEvent = true
        defer { handlingSendEvent = previous }
        super.sendEvent(event)
    }
}
