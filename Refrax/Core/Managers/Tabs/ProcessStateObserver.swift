import Foundation
import Observation
import WebKit

/// Observes web process state changes with `@Observable` integration.
///
/// `ProcessStateObserver` provides reactive access to the underlying `WKWebView`'s
/// process state via KVO, using the same pattern as `WebPage` for proper SwiftUI
/// integration. Views observing these properties will automatically update when
/// the web process state changes.
///
/// ## Overview
///
/// The observer tracks three key aspects of process health:
/// - **Process state**: Running, suspended, or terminated (`_webProcessState`)
/// - **Responsiveness**: Whether the process is responding to IPC
/// - **Recent crash**: Whether the tab recently crashed and was recovered
///
/// ## Debouncing
///
/// The raw WebKit process state can briefly report `notRunning` during process
/// startup before transitioning to a running state. To prevent UI flicker, this
/// observer debounces the transition TO `notRunning`:
///
/// - Transitions TO running states (foreground/background/suspended) are immediate
/// - Transitions TO `notRunning` are delayed by 500ms
/// - If the process becomes running within the delay, `notRunning` is never reported
///
/// This ensures the suspended indicator doesn't flash during WebView creation.
///
/// ## Usage
///
/// ```swift
/// let observer = ProcessStateObserver(wkWebView: session.wkWebView)
///
/// // In SwiftUI view - will automatically update
/// if observer.processState == .notRunning {
///     UnloadedTabOverlay()
/// }
///
/// if observer.isUnresponsive {
///     UnresponsiveIndicator()
/// }
/// ```
///
/// ## KVO Pattern
///
/// Uses the same backing property pattern as `WebPage` to properly integrate
/// KVO-based properties with Swift's `@Observable` macro. This ensures that
/// SwiftUI views receive updates when the underlying KVO properties change.
@Observable
final class ProcessStateObserver {
    // MARK: - Observable Properties

    /// Current state of the web process (debounced).
    ///
    /// Debounces transitions TO `notRunning` to prevent UI flicker during
    /// process startup. Transitions to running states are immediate.
    private(set) var processState: _WKWebProcessState = .notRunning

    /// Whether the web process is currently unresponsive.
    ///
    /// Set via delegate callbacks from `WKNavigationDelegatePrivate`.
    /// Reset when the process becomes responsive or terminates.
    private(set) var isUnresponsive: Bool = false

    /// Whether the tab recently crashed and was auto-recovered.
    ///
    /// Used to show a visual indicator that recovery occurred.
    /// Automatically cleared after a brief display period.
    private(set) var recentlyCrashed: Bool = false

    /// Whether the process has ever been in a running state.
    ///
    /// Used to distinguish between:
    /// - A page that crashed/terminated (was running, now not) → show unloaded indicator
    /// - A new page that hasn't loaded yet → don't show indicator
    private(set) var hasEverBeenRunning: Bool = false

    /// The reason for the most recent process termination.
    ///
    /// `nil` if no termination has occurred during this observer's lifetime.
    private(set) var lastTerminationReason: _WKProcessTerminationReason?

    /// Timestamp of the most recent termination.
    private(set) var lastTerminationTime: Date?

    // MARK: - Computed Properties

    /// Whether the web process is alive (running in any state).
    var isAlive: Bool {
        processState != .notRunning
    }

    /// Whether the tab content needs reload to display.
    ///
    /// True when the process was running but has since terminated.
    /// Returns false for new pages that haven't loaded yet to avoid flashing the indicator.
    var needsReload: Bool {
        hasEverBeenRunning && processState == .notRunning
    }

    /// Whether the process is running in the foreground with full priority.
    var isForeground: Bool {
        processState == .foreground
    }

    /// Whether the process is suspended (frozen, not executing).
    var isSuspended: Bool {
        processState == .suspended
    }

    // MARK: - Private

    private let wkWebView: WKWebView

    @ObservationIgnored
    private var observations = ObservationStorage()

    @ObservationIgnored
    private var crashIndicatorTask: Task<Void, any Error>?

    /// Task for debouncing the transition to `notRunning`.
    @ObservationIgnored
    private var notRunningDebounceTask: Task<Void, Never>?

    /// Delay before reporting `notRunning` state.
    /// Long enough to span process startup race conditions including cold launches.
    private static let notRunningDebounceDelay: Duration = .seconds(1)

    // MARK: - Initialization

    /// Creates an observer for the given web view's process state.
    ///
    /// - Parameter wkWebView: The `WKWebView` to observe.
    init(wkWebView: WKWebView) {
        self.wkWebView = wkWebView
        startProcessStateObservation()
    }

    isolated deinit {
        crashIndicatorTask?.cancel()
        notRunningDebounceTask?.cancel()
    }

    // MARK: - Process State Observation

    /// Starts KVO observation of process state with debouncing logic.
    private func startProcessStateObservation() {
        let keyPath = \WKWebView._webProcessState

        let observation = wkWebView.observe(keyPath, options: [.initial, .new]) { [weak self] webView, _ in
            guard let self else { return }

            // KVO callbacks come from main thread for WKWebView
            MainActor.assumeIsolated {
                let rawState = webView._webProcessState
                handleRawProcessStateChange(rawState)
            }
        }

        observations.contents[\ProcessStateObserver.processState] = observation
    }

    /// Handles raw process state changes with debouncing for `notRunning`.
    ///
    /// Since `processState` is a stored property, the `@Observable` macro
    /// automatically handles `willSet`/`didSet` notifications when we assign to it.
    private func handleRawProcessStateChange(_ rawState: _WKWebProcessState) {
        // Cancel any pending debounce
        notRunningDebounceTask?.cancel()
        notRunningDebounceTask = nil

        if rawState == .notRunning {
            // Debounce transition TO notRunning
            notRunningDebounceTask = Task { [weak self] in
                try? await Task.sleep(for: Self.notRunningDebounceDelay)
                guard !Task.isCancelled, let self else { return }

                // Double-check the raw state is still notRunning after debounce
                guard wkWebView._webProcessState == .notRunning else { return }

                // Now report notRunning - @Observable handles notifications automatically
                processState = .notRunning
            }
        } else {
            // Immediate transition to running states
            if processState != rawState {
                processState = rawState
            }
            // Track that the process has been running at least once
            if !hasEverBeenRunning {
                hasEverBeenRunning = true
            }
        }
    }

    // MARK: - State Updates

    /// Records that the process became unresponsive.
    ///
    /// Called from navigation delegate when `_webViewWebProcessDidBecomeUnresponsive:`
    /// is received.
    func markUnresponsive() {
        isUnresponsive = true
        Logger.warning("Web process became unresponsive", category: Logger.tabs)
    }

    /// Records that the process became responsive again.
    ///
    /// Called from navigation delegate when `_webViewWebProcessDidBecomeResponsive:`
    /// is received.
    func markResponsive() {
        isUnresponsive = false
        Logger.info("Web process became responsive", category: Logger.tabs)
    }

    /// Records a process termination event.
    ///
    /// Called from navigation delegate when process termination is detected.
    ///
    /// - Parameter reason: The reason for termination.
    func recordTermination(reason: _WKProcessTerminationReason) {
        lastTerminationReason = reason
        lastTerminationTime = Date()
        isUnresponsive = false

        Logger.info(
            "Web process terminated: \(reason.logDescription)",
            category: Logger.tabs,
        )
    }

    /// Marks the tab as recently crashed for visual indication.
    ///
    /// The `recentlyCrashed` flag is automatically cleared after a brief period.
    ///
    /// - Parameter duration: How long to show the crash indicator.
    func showCrashIndicator(for duration: Duration = .seconds(5)) {
        recentlyCrashed = true

        crashIndicatorTask?.cancel()
        crashIndicatorTask = Task { [weak self] in
            try await Task.sleep(for: duration)
            self?.recentlyCrashed = false
        }
    }

    /// Clears the crash indicator immediately.
    func clearCrashIndicator() {
        crashIndicatorTask?.cancel()
        crashIndicatorTask = nil
        recentlyCrashed = false
    }
}

// MARK: - Observation Storage

/// Storage for KVO observations.
///
/// This class is only accessed from `@MainActor` context (via `ProcessStateObserver`).
/// The `invalidateAll()` method can be safely called from deinit since
/// `NSKeyValueObservation.invalidate()` is thread-safe.
private final class ObservationStorage {
    var contents: [AnyKeyPath: NSKeyValueObservation] = [:]

    /// Invalidates all observations. Safe to call from deinit.
    func invalidateAll() {
        for observation in contents.values {
            observation.invalidate()
        }
        contents.removeAll()
    }
}

// MARK: - _WKProcessTerminationReason Extensions

extension _WKProcessTerminationReason {
    /// Whether the termination is recoverable via automatic reload.
    var isRecoverable: Bool {
        switch self {
        case .exceededMemoryLimit, .crash, .exceededCPULimit, .exceededSharedProcessCrashLimit:
            true
        case .requestedByClient:
            false
        @unknown default:
            false
        }
    }

    /// Whether the user should be notified of this termination.
    var shouldNotifyUser: Bool {
        switch self {
        case .crash, .exceededSharedProcessCrashLimit:
            true
        case .exceededMemoryLimit, .exceededCPULimit, .requestedByClient:
            false
        @unknown default:
            false
        }
    }

    /// Suggested delay before attempting recovery reload.
    var recoveryDelay: Duration {
        switch self {
        case .exceededMemoryLimit:
            .seconds(1)
        case .exceededCPULimit:
            .seconds(2)
        case .crash, .exceededSharedProcessCrashLimit:
            .milliseconds(500)
        case .requestedByClient:
            .zero
        @unknown default:
            .milliseconds(500)
        }
    }

    /// Human-readable description for logging.
    var logDescription: String {
        switch self {
        case .exceededMemoryLimit:
            "exceeded memory limit (OOM)"
        case .exceededCPULimit:
            "exceeded CPU limit"
        case .requestedByClient:
            "requested by client"
        case .crash:
            "crashed"
        case .exceededSharedProcessCrashLimit:
            "exceeded shared process crash limit"
        @unknown default:
            "unknown reason (\(rawValue))"
        }
    }

    /// User-facing description for toast messages.
    var userDescription: String {
        switch self {
        case .exceededMemoryLimit:
            "ran out of memory"
        case .exceededCPULimit:
            "was using too much CPU"
        case .crash, .exceededSharedProcessCrashLimit:
            "crashed unexpectedly"
        case .requestedByClient:
            "was closed"
        @unknown default:
            "encountered an error"
        }
    }
}

// MARK: - _WKWebProcessState Extensions

extension _WKWebProcessState {
    /// Human-readable description for logging.
    var logDescription: String {
        switch self {
        case .notRunning:
            "not running"
        case .foreground:
            "foreground"
        case .background:
            "background"
        case .suspended:
            "suspended"
        @unknown default:
            "unknown (\(rawValue))"
        }
    }
}
