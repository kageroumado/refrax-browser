import Foundation
import Observation

/// Handles web content process termination events and automatic recovery.
///
/// `WebProcessTerminationHandler` receives termination notifications from
/// `WKNavigationDelegatePrivate` and coordinates:
/// - Automatic reload for recoverable terminations
/// - Crash frequency tracking to detect problematic sites
/// - User notification via toast for unexpected crashes
/// - Suppression of reload loops for repeatedly crashing pages
///
/// ## Crash Detection Philosophy
///
/// The handler uses a "three strikes" approach:
/// - First crash: Auto-reload silently
/// - Second crash: Auto-reload with toast notification
/// - Third crash within 60 seconds: Suppress reload, show persistent error
///
/// This prevents infinite reload loops while still recovering from transient issues.
///
/// ## Usage
///
/// ```swift
/// let handler = WebProcessTerminationHandler()
/// handler.toastPresenter = { message in
///     ToastManager.shared.show(message)
/// }
///
/// // In navigation delegate:
/// func _webView(_ webView: WKWebView,
///               webContentProcessDidTerminateWithReason reason: _WKProcessTerminationReason) {
///     guard let page = pagePool.page(for: webView) else { return }
///     handler.handleTermination(for: page, reason: reason)
/// }
/// ```
@Observable
final class WebProcessTerminationHandler {
    // MARK: - Configuration

    /// Reference to browser settings for checking crash recovery preferences.
    private weak var settings: BrowserSettings?

    /// Number of crashes within the time window before suppressing reload.
    ///
    /// Synced from `BrowserSettings.crashThreshold`.
    var crashThreshold: Int = 3

    /// Time window for tracking crash frequency (seconds).
    ///
    /// Synced from `BrowserSettings.crashTimeWindowSeconds`.
    var crashTimeWindow: TimeInterval = 60

    /// Whether automatic crash recovery is enabled.
    ///
    /// When `false`, crashed tabs are not automatically reloaded.
    var enableAutoCrashRecovery: Bool {
        settings?.enableAutoCrashRecovery ?? true
    }

    // MARK: - State

    /// Termination history per tab page, keyed by page ID.
    private(set) var terminationHistory: [UUID: [TerminationEvent]] = [:]

    /// Pages currently in "problematic" state (exceeded crash threshold).
    private(set) var problematicPages: Set<UUID> = []

    // MARK: - Callbacks

    /// Called to present a toast message to the user.
    var toastPresenter: ((String) -> Void)?

    /// Called when a page exceeds the crash threshold.
    var onProblematicPage: ((WebPage, Int) -> Void)?

    /// Called after a page has been recovered from a crash.
    var onPageRecovered: ((WebPage) -> Void)?

    // MARK: - Types

    /// Records a single termination event for analytics and throttling.
    struct TerminationEvent: Sendable {
        let reason: _WKProcessTerminationReason
        let timestamp: Date
        let url: URL?

        /// Whether this event represents a true crash (not intentional termination).
        var isCrash: Bool {
            reason == .crash || reason == .exceededSharedProcessCrashLimit
        }
    }

    // MARK: - Initialization

    init() {}

    /// Configures the handler with browser settings.
    ///
    /// Call this after initialization to sync crash recovery settings.
    ///
    /// - Parameter settings: The browser settings to read preferences from.
    func configure(with settings: BrowserSettings) {
        self.settings = settings
        crashThreshold = settings.crashThreshold
        crashTimeWindow = TimeInterval(settings.crashTimeWindowSeconds)
    }

    // MARK: - Termination Handling

    /// Handles a process termination event for a page.
    ///
    /// This method:
    /// 1. Records the termination for crash frequency tracking
    /// 2. Determines if auto-reload should be attempted
    /// 3. Schedules recovery if appropriate
    /// 4. Notifies the user if needed
    ///
    /// - Parameters:
    ///   - page: The page whose process terminated.
    ///   - reason: The reason for termination.
    func handleTermination(
        for page: WebPage,
        reason: _WKProcessTerminationReason,
    ) {
        let pageID = page.tabPage.id
        let event = TerminationEvent(
            reason: reason,
            timestamp: Date(),
            url: page.tabPage.url,
        )

        recordTermination(event, for: pageID)

        Logger.info(
            "Process terminated for '\(page.tabPage.title)': \(reason.logDescription)",
            category: Logger.tabs,
        )

        // Report true crashes (not memory/CPU evictions) to crash telemetry
        if event.isCrash, let settings {
            TelemetryService.sendCrashReport(
                reason: reason.telemetryReason,
                domain: page.tabPage.url.registrableDomain ?? "unknown",
                settings: settings,
            )
        }

        // Update page's process state observer
        page.processStateObserver?.recordTermination(reason: reason)

        // Check if automatic crash recovery is disabled
        guard enableAutoCrashRecovery else {
            Logger.info("Automatic crash recovery disabled, skipping reload", category: Logger.tabs)
            page.crashError = CrashError(
                reason: reason,
                crashCount: 1,
                url: page.tabPage.url,
                timestamp: Date()
            )
            return
        }

        // Check if page is problematic
        if shouldSuppressReload(for: pageID) {
            handleProblematicPage(page: page, event: event)
            return
        }

        // Attempt recovery for recoverable terminations
        if reason.isRecoverable {
            scheduleRecovery(for: page, reason: reason, event: event)
        }
    }

    /// Handles unresponsive process notification.
    ///
    /// - Parameter page: The page whose process became unresponsive.
    func handleUnresponsive(for page: WebPage) {
        page.processStateObserver?.markUnresponsive()

        Logger.warning(
            "Process unresponsive for '\(page.tabPage.title)'",
            category: Logger.tabs,
        )
    }

    /// Handles responsive process notification.
    ///
    /// - Parameter page: The page whose process became responsive.
    func handleResponsive(for page: WebPage) {
        page.processStateObserver?.markResponsive()

        Logger.info(
            "Process responsive for '\(page.tabPage.title)'",
            category: Logger.tabs,
        )
    }

    // MARK: - Crash Tracking

    /// Records a termination event for a page.
    private func recordTermination(_ event: TerminationEvent, for pageID: UUID) {
        var history = terminationHistory[pageID] ?? []
        history.append(event)

        // Keep only recent events within the time window
        let cutoff = Date().addingTimeInterval(-crashTimeWindow)
        history = history.filter { $0.timestamp > cutoff }

        terminationHistory[pageID] = history
    }

    /// Determines if reload should be suppressed for a page.
    ///
    /// Returns `true` if the page has crashed too many times recently.
    private func shouldSuppressReload(for pageID: UUID) -> Bool {
        guard let history = terminationHistory[pageID] else { return false }

        let cutoff = Date().addingTimeInterval(-crashTimeWindow)
        let recentCrashes = history.filter {
            $0.isCrash && $0.timestamp > cutoff
        }

        return recentCrashes.count >= crashThreshold
    }

    /// Returns the number of recent crashes for a page.
    func recentCrashCount(for pageID: UUID) -> Int {
        guard let history = terminationHistory[pageID] else { return 0 }

        let cutoff = Date().addingTimeInterval(-crashTimeWindow)
        return history.count(where: { $0.isCrash && $0.timestamp > cutoff })
    }

    // MARK: - Recovery

    /// Schedules automatic recovery reload for a crashed tab.
    private func scheduleRecovery(
        for page: WebPage,
        reason: _WKProcessTerminationReason,
        event _: TerminationEvent,
    ) {
        let pageID = page.tabPage.id
        let crashCount = recentCrashCount(for: pageID)

        Task {
            // Wait before reloading
            try? await Task.sleep(for: reason.recoveryDelay)

            // Verify page is still valid
            guard page.tabPage.tab != nil else {
                Logger.debug(
                    "Skipping recovery - tab was closed",
                    category: Logger.tabs,
                )
                return
            }

            // Reload from persisted URL
            page.load(page.tabPage.url)

            // Show crash indicator on tab
            page.processStateObserver?.showCrashIndicator()

            // Notify recovery callback (e.g., for screen share audio re-unmuting)
            onPageRecovered?(page)

            Logger.info(
                "Auto-recovered '\(page.tabPage.title)' (crash #\(crashCount))",
                category: Logger.tabs,
            )

            // Notify user if this is a repeated crash or explicit crash
            if reason.shouldNotifyUser || crashCount > 1 {
                showRecoveryToast(for: page, reason: reason)
            }
        }
    }

    /// Handles a page that has exceeded the crash threshold.
    private func handleProblematicPage(page: WebPage, event: TerminationEvent) {
        let pageID = page.tabPage.id
        problematicPages.insert(pageID)

        let crashCount = recentCrashCount(for: pageID)

        Logger.fault(
            "Page '\(page.tabPage.title)' exceeded crash threshold (\(crashCount) crashes in \(Int(crashTimeWindow))s)",
            category: Logger.tabs,
        )

        // Show crash error page with actionable information
        page.crashError = CrashError(
            reason: event.reason,
            crashCount: crashCount,
            url: page.tabPage.url,
            timestamp: Date()
        )

        // Notify callback
        onProblematicPage?(page, crashCount)
    }

    /// Shows a toast notification about crash recovery.
    private func showRecoveryToast(for page: WebPage, reason: _WKProcessTerminationReason) {
        let title = page.tabPage.title.isEmpty
            ? "Page"
            : "\"\(page.tabPage.title.prefix(30))\""

        let message = "\(title) \(reason.userDescription) and was reloaded"
        toastPresenter?(message)
    }

    // MARK: - State Management

    /// Clears termination history for a page.
    ///
    /// Call when a tab is closed to free memory.
    func clearHistory(for pageID: UUID) {
        terminationHistory.removeValue(forKey: pageID)
        problematicPages.remove(pageID)
    }

    /// Transfers termination history from one page ID to another.
    ///
    /// Call during page transfer to preserve crash tracking state.
    ///
    /// - Parameters:
    ///   - sourceID: The original page ID.
    ///   - destinationID: The new page ID.
    func transferHistory(from sourceID: UUID, to destinationID: UUID) {
        if let history = terminationHistory.removeValue(forKey: sourceID) {
            terminationHistory[destinationID] = history
        }

        if problematicPages.remove(sourceID) != nil {
            problematicPages.insert(destinationID)
        }
    }

    /// Clears the problematic state for a page.
    ///
    /// Call after user manually reloads to give the page another chance.
    func clearProblematicState(for pageID: UUID) {
        problematicPages.remove(pageID)
        // Also clear recent crash history to reset the threshold
        terminationHistory.removeValue(forKey: pageID)
    }

    /// Whether a page is currently in problematic state.
    func isProblematic(_ pageID: UUID) -> Bool {
        problematicPages.contains(pageID)
    }

    // MARK: - Diagnostics

    /// Returns diagnostic information about termination history.
    func diagnostics() -> [String: Any] {
        var info: [String: Any] = [
            "crashThreshold": crashThreshold,
            "crashTimeWindow": crashTimeWindow,
            "problematicPageCount": problematicPages.count,
            "trackedPageCount": terminationHistory.count,
        ]

        // Summary of recent terminations
        var terminationSummary: [[String: Any]] = []
        for (pageID, events) in terminationHistory {
            let recentEvents = events.suffix(5)
            for event in recentEvents {
                terminationSummary.append([
                    "pageID": pageID.uuidString.prefix(8),
                    "reason": event.reason.logDescription,
                    "timestamp": event.timestamp,
                    "url": event.url?.host ?? "unknown",
                ])
            }
        }
        info["recentTerminations"] = terminationSummary

        return info
    }
}
