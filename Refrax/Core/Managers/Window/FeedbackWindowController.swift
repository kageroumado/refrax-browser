import AppKit
import SwiftUI

/// Manages the feedback compose window.
///
/// Entry points: Help menu "Send Feedback...", Command Lens, agent tools.
final class FeedbackWindowController {
    private var window: NSWindow?
    private let feedbackManager: FeedbackManager

    init(feedbackManager: FeedbackManager) {
        self.feedbackManager = feedbackManager
    }

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = createWindow()
        window = newWindow

        Task { await feedbackManager.prepareForPresentation() }

        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() -> NSWindow {
        let feedbackView = FeedbackView()
            .environment(feedbackManager)

        let hostingController = NSHostingController(rootView: feedbackView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Send Feedback"
        window.styleMask = [.titled, .closable]
        window.titlebarSeparatorStyle = .none
        window.setContentSize(NSSize(width: 480, height: 600))
        window.isRestorable = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.feedbackManager.reset()
                self?.window = nil
            }
        }

        return window
    }
}
