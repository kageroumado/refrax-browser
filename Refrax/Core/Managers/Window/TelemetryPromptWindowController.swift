import AppKit
import SwiftUI

/// The one-time window asking an install that finished onboarding to choose a telemetry tier.
///
/// Continue saves the selected tier. Closing the window saves ``TelemetryTier/off``,
/// so the prompt never returns.
final class TelemetryPromptWindowController {
    private var window: NSWindow?
    private var settings: BrowserSettings?

    /// Called once the window has closed, by either route.
    var onClosed: (() -> Void)?

    func showWindow(settings: BrowserSettings) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.settings = settings

        let view = OnboardingTelemetryView(
            note: "Refrax is out of alpha, so telemetry is now your choice.",
        ) { [weak self] in
            self?.window?.close()
        }
        .environment(settings)
        .frame(width: 520, height: 720)
        .background(Color(.windowBackgroundColor))

        let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
        newWindow.title = "Telemetry"
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.titlebarSeparatorStyle = .none
        newWindow.isRestorable = false
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowWillClose()
            }
        }

        window = newWindow
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
    }

    private func windowWillClose() {
        if let settings, settings.telemetryTierRaw == nil {
            settings.telemetryTier = .off
        }
        window = nil
        onClosed?()
    }
}
