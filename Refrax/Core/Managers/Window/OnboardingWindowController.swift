import AppKit
import SwiftData
import SwiftUI

/// Manages the onboarding window shown on first launch.
///
/// Presents a chromeless window with the onboarding flow.
/// The close button quits the app — users cannot bypass activation.
final class OnboardingWindowController {
    private var window: NSWindow?

    /// Called when the user completes the onboarding flow.
    var onCompleted: (() -> Void)?

    func showWindow(
        settings: BrowserSettings,
        bookmarksManager: BookmarksManager,
        historyManager: HistoryManager,
        passwordsManager: PasswordsManager,
        modelContainer: ModelContainer
    ) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let containerView = OnboardingContainerView {
            self.onCompleted?()
        }
        .environment(settings)
        .environment(bookmarksManager)
        .environment(historyManager)
        .environment(passwordsManager)
        .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: containerView)
        let newWindow = NSWindow(contentViewController: hostingController)

        newWindow.title = "Welcome to Refrax"
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.titlebarSeparatorStyle = .none
        newWindow.isRestorable = false
        newWindow.isMovableByWindowBackground = true
        newWindow.setContentSize(NSSize(width: 520, height: 640))
        newWindow.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.window != nil {
                    self?.window = nil
                    NSApp.terminate(nil)
                }
            }
        }

        window = newWindow
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the onboarding window without quitting the app.
    ///
    /// Called when onboarding completes successfully.
    func closeWindow() {
        let w = window
        window = nil
        w?.close()
    }
}
