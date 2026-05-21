import AppKit
import Observation

/// Observes whether an NSWindow is being captured by an external screen sharing session.
///
/// This observer monitors the private `hasActiveWindowSharingSession` property on NSWindow
/// via KVO to detect when external applications (Zoom, FaceTime, ScreenCaptureKit-based apps)
/// are capturing the window or screen.
///
/// ## Potential Use Cases
///
/// - Show an indicator when the window is being shared
/// - Adjust UI for better visibility during screen sharing
/// - Log screen sharing activity for debugging
///
/// ## WKWebView Audio Limitation
///
/// Note: This observer cannot be used to enable WKWebView audio capture by external apps.
/// WKWebView audio runs in a separate process (WebContent/GPU) that ScreenCaptureKit
/// cannot capture. This is a known WebKit architecture limitation.
/// See `WKWebViewPrivate+Media.h` for details.
///
/// ## Implementation Notes
///
/// The `hasActiveWindowSharingSession` property is declared in `NSWindowPrivate.h`.
/// It returns `true` when the window is being captured via:
/// - Screen sharing (Zoom, Teams, FaceTime, etc.)
/// - AirPlay mirroring
/// - ScreenCaptureKit-based applications
/// - QuickTime screen recording
@Observable
final class WindowSharingObserver {
    // MARK: - Observable State

    /// Whether the window is currently being captured by an external application.
    ///
    /// When `true`, the window or screen containing it is being shared.
    private(set) var isWindowBeingShared: Bool = false

    // MARK: - Private Properties

    @ObservationIgnored
    private weak var window: NSWindow?

    @ObservationIgnored
    private var kvoObservation: NSKeyValueObservation?

    // MARK: - Initialization

    /// Creates a new observer for the specified window.
    ///
    /// The observer immediately reads the current sharing state and begins
    /// monitoring for changes.
    ///
    /// - Parameter window: The window to observe for screen sharing.
    init(window: NSWindow) {
        self.window = window

        // Read initial state
        self.isWindowBeingShared = window.hasActiveWindowSharingSession

        // Set up KVO observation
        setupObservation()
    }

    deinit {
        kvoObservation?.invalidate()
    }

    // MARK: - Private Methods

    private func setupObservation() {
        guard let window else { return }

        // Use modern Swift KVO for type safety
        // Dispatch to main queue since KVO callbacks may come from any thread
        // and isWindowBeingShared is MainActor-isolated
        kvoObservation = window.observe(
            \.hasActiveWindowSharingSession,
            options: [.new],
        ) { [weak self] _, change in
            let newValue = change.newValue ?? false

            DispatchQueue.main.async {
                self?.updateSharingState(newValue)
            }
        }
    }

    private func updateSharingState(_ newValue: Bool) {
        guard isWindowBeingShared != newValue else { return }
        isWindowBeingShared = newValue

        Logger.debug(
            "Window sharing state changed: \(newValue)",
            category: Logger.webview,
        )
    }
}
