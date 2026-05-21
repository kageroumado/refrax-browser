import AppKit

/// Handles window restoration for app relaunch
///
/// This restoration class is called by AppKit when restoring windows after app relaunch.
/// It creates the window and window controller, registers them with WindowManager, and then
/// AppKit automatically calls the window controller's `didDecodeRestorableState` to restore UI state.
final class RefraxWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state _: NSCoder,
        completionHandler: @escaping (NSWindow?, (any Error)?) -> Void,
    ) {
        #if DEBUG
            debugPrint("🟡 Restoring window with identifier: \(identifier)")
        #endif
        
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            completionHandler(nil, NSError(domain: "RefraxWindowRestoration", code: 1))
            return
        }

        // Don't restore windows if onboarding hasn't been completed.
        // The onboarding gate in applicationDidFinishLaunching will handle
        // showing the onboarding window and creating the first browser window.
        guard appDelegate.browserState.settings.hasCompletedOnboarding else {
            completionHandler(nil, nil)
            return
        }

        let window = RefraxWindow()
        let windowController = RefraxWindowController(window: window)

        appDelegate.windowManager.registerWindowController(windowController)

        completionHandler(window, nil)
    }
}
