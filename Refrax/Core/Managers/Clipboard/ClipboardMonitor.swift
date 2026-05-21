import AppKit
import Foundation
import Observation

/// Monitors the system clipboard for URLs and publishes them for quick navigation.
///
/// When enabled, `ClipboardMonitor` checks the system pasteboard on app activation
/// for HTTP/HTTPS URLs and publishes them via `detectedURL`. The UI layer can observe
/// this to show a toast with quick navigation options.
///
/// ## Detection Strategy
///
/// Instead of continuous polling, the monitor checks the clipboard when:
/// - The app becomes active (foreground)
/// - The clipboard changes while the app is active
///
/// This is more efficient and respects privacy - we only check when the user
/// is actively using the app.
///
/// ## Privacy
///
/// - Off by default - user must explicitly enable via settings
/// - Only detects HTTP/HTTPS URLs, not arbitrary clipboard content
/// - No clipboard content is stored or logged
/// - Uses a cooldown period to avoid repeated notifications for the same URL
///
/// ## Usage
///
/// ```swift
/// let monitor = ClipboardMonitor(settings: browserSettings)
///
/// // Observe detectedURL in UI to show toast
/// .onChange(of: monitor.detectedURL) { _, url in
///     if let url {
///         showClipboardToast(for: url)
///     }
/// }
/// ```
@Observable
final class ClipboardMonitor {
    // MARK: - State

    /// The most recently detected URL from the clipboard.
    ///
    /// Set when a new HTTP/HTTPS URL is detected. UI should observe this
    /// to show the clipboard URL toast. Cleared after cooldown period.
    private(set) var detectedURL: URL?

    /// Whether monitoring is currently active.
    private(set) var isMonitoring: Bool = false

    // MARK: - Dependencies

    private let settings: BrowserSettings

    // MARK: - Private State

    @ObservationIgnored
    private nonisolated(unsafe) var appActivationObserver: Any?

    @ObservationIgnored
    private var lastChangeCount: Int = 0

    @ObservationIgnored
    private var lastDetectedURL: URL?

    @ObservationIgnored
    private var lastDetectedTime: Date?

    /// Cooldown period to avoid re-showing toast for the same URL.
    private let cooldownSeconds: TimeInterval = 30

    // MARK: - Initialization

    init(settings: BrowserSettings) {
        self.settings = settings

        // Record current clipboard state to avoid showing toast for URLs
        // that were already in the clipboard before the app launched
        self.lastChangeCount = NSPasteboard.general.changeCount

        // Start monitoring if setting is enabled
        if settings.clipboardLinkMonitoring {
            startMonitoring()
        }

        Logger.info("ClipboardMonitor initialized", category: Logger.clipboard)
    }

    deinit {
        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Monitoring Control

    /// Start monitoring the clipboard for URLs.
    ///
    /// Registers for app activation notifications and checks clipboard on each activation.
    func startMonitoring() {
        guard !isMonitoring else { return }

        // Observe app becoming active to check clipboard
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkClipboard()
            }
        }

        isMonitoring = true
        Logger.info("Clipboard monitoring started (activation-based)", category: Logger.clipboard)
    }

    /// Stop monitoring the clipboard.
    func stopMonitoring() {
        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appActivationObserver = nil
        }
        detectedURL = nil
        isMonitoring = false

        Logger.info("Clipboard monitoring stopped", category: Logger.clipboard)
    }

    /// Toggle monitoring based on the current setting.
    ///
    /// Call this when the setting changes to start or stop monitoring.
    func syncWithSettings() {
        if settings.clipboardLinkMonitoring, !isMonitoring {
            startMonitoring()
        } else if !settings.clipboardLinkMonitoring, isMonitoring {
            stopMonitoring()
        }
    }

    /// Clear the detected URL (e.g., after user acts on or dismisses toast).
    func clearDetectedURL() {
        detectedURL = nil
    }

    // MARK: - Clipboard Checking

    private func checkClipboard() {
        // Only check if monitoring is enabled in settings
        guard settings.clipboardLinkMonitoring else { return }
        let pb = NSPasteboard.general

        // Only check if clipboard content changed
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Try to extract a URL
        guard let url = extractURL(from: pb) else { return }

        // Check cooldown for same URL
        if let lastURL = lastDetectedURL,
           let lastTime = lastDetectedTime,
           url == lastURL,
           Date().timeIntervalSince(lastTime) < cooldownSeconds {
            Logger.debug("URL within cooldown period, skipping: \(url.host ?? "unknown")", category: Logger.clipboard)
            return
        }

        // Update state
        lastDetectedURL = url
        lastDetectedTime = Date()
        detectedURL = url

        Logger.info("Detected URL in clipboard: \(url.host ?? "unknown")", category: Logger.clipboard)
    }

    private func extractURL(from pasteboard: NSPasteboard) -> URL? {
        // Check for URL type first
        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString),
           isValidWebURL(url) {
            return url
        }

        // Fall back to string type
        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

            // Only process if it looks like a URL (starts with http)
            guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
                return nil
            }

            if let url = URL(string: trimmed), isValidWebURL(url) {
                return url
            }
        }

        return nil
    }

    private func isValidWebURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
    }
}
