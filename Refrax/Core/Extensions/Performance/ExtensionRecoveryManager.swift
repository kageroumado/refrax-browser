import Foundation
import Observation
import UserNotifications
import WebKit

/// Manages crash detection and recovery for browser extensions.
///
/// This manager monitors extension contexts for errors and implements smart recovery:
/// - Automatically restarts crashed extensions (up to 3 times per hour)
/// - Uses exponential backoff between restart attempts
/// - Disables extensions that crash repeatedly
/// - Maintains an error log for user review
///
/// ## Recovery Policy
///
/// 1. On first crash: Restart immediately
/// 2. On second crash within 1 hour: Wait 5 seconds, then restart
/// 3. On third crash within 1 hour: Wait 30 seconds, then restart
/// 4. On fourth crash within 1 hour: Disable extension, notify user
///
/// After 1 hour without crashes, the crash counter resets.
@Observable
final class ExtensionRecoveryManager {
    // MARK: - Types

    /// An error event logged for an extension.
    struct ErrorLogEntry: Identifiable, Sendable, Equatable {
        let id: UUID
        let extensionID: String
        let extensionName: String
        let error: String
        let timestamp: Date
        let severity: Severity
        let wasRecovered: Bool

        enum Severity: String, Sendable {
            case warning
            case error
            case crash
        }

        init(
            extensionID: String,
            extensionName: String,
            error: String,
            severity: Severity,
            wasRecovered: Bool = false,
        ) {
            self.id = UUID()
            self.extensionID = extensionID
            self.extensionName = extensionName
            self.error = error
            self.timestamp = Date()
            self.severity = severity
            self.wasRecovered = wasRecovered
        }
    }

    /// Recovery state for a single extension.
    private struct RecoveryState {
        var crashTimestamps: [Date] = []
        var lastRestartAttempt: Date?
        var isDisabledDueToCrashes: Bool = false
    }

    // MARK: - Configuration

    /// Maximum crashes allowed within the reset window.
    let maxCrashesBeforeDisable = 3

    /// Time window for counting crashes (1 hour).
    let crashCountResetWindow: TimeInterval = 3_600

    /// Backoff delays for restart attempts.
    let backoffDelays: [TimeInterval] = [0, 5, 30]

    // MARK: - State

    /// Error log entries for UI display.
    private(set) var errorLog: [ErrorLogEntry] = []

    /// Maximum error log entries to retain.
    let maxErrorLogEntries = 100

    /// Recovery state per extension.
    private var recoveryStates: [String: RecoveryState] = [:]

    /// Pending restart tasks.
    private var pendingRestarts: [String: Task<Void, Never>] = [:]

    /// Reference to extension manager for restart operations.
    weak var extensionManager: ExtensionManager?

    // MARK: - Error Handling

    /// Records an error for an extension.
    ///
    /// This method logs the error and determines if recovery action is needed.
    ///
    /// - Parameters:
    ///   - error: The error that occurred.
    ///   - extension_: The extension that encountered the error.
    ///   - isCrash: Whether this error caused the extension to crash.
    func recordError(
        _ error: any Error,
        for extension_: InstalledExtension,
        isCrash: Bool = false,
    ) {
        let extensionID = extension_.uniqueIdentifier

        // Create log entry
        let entry = ErrorLogEntry(
            extensionID: extensionID,
            extensionName: extension_.displayName,
            error: error.localizedDescription,
            severity: isCrash ? .crash : .error,
        )

        addLogEntry(entry)

        Logger.error(
            "Extension '\(extension_.displayName)' error: \(error.localizedDescription)",
            category: Logger.extensions,
        )

        if isCrash {
            handleCrash(for: extension_)
        }
    }

    /// Records a warning for an extension.
    ///
    /// - Parameters:
    ///   - message: The warning message.
    ///   - extension_: The extension to warn about.
    func recordWarning(_ message: String, for extension_: InstalledExtension) {
        let entry = ErrorLogEntry(
            extensionID: extension_.uniqueIdentifier,
            extensionName: extension_.displayName,
            error: message,
            severity: .warning,
        )

        addLogEntry(entry)

        Logger.warning(
            "Extension '\(extension_.displayName)' warning: \(message)",
            category: Logger.extensions,
        )
    }

    // MARK: - Crash Recovery

    /// Handles a crash for an extension.
    private func handleCrash(for extension_: InstalledExtension) {
        let extensionID = extension_.uniqueIdentifier
        let now = Date()

        // Get or create recovery state
        var state = recoveryStates[extensionID] ?? RecoveryState()

        // Remove old crash timestamps outside the reset window
        state.crashTimestamps = state.crashTimestamps.filter {
            now.timeIntervalSince($0) < crashCountResetWindow
        }

        // Add this crash
        state.crashTimestamps.append(now)

        // Check if we should disable
        if state.crashTimestamps.count > maxCrashesBeforeDisable {
            disableExtension(extension_, state: &state)
            recoveryStates[extensionID] = state
            return
        }

        // Schedule restart with backoff
        let crashCount = state.crashTimestamps.count
        let delay = backoffDelays[min(crashCount - 1, backoffDelays.count - 1)]

        Logger.info(
            "Extension '\(extension_.displayName)' crashed (\(crashCount)/\(maxCrashesBeforeDisable)). " +
                "Restarting in \(delay) seconds.",
            category: Logger.extensions,
        )

        scheduleRestart(for: extension_, delay: delay)

        recoveryStates[extensionID] = state
    }

    /// Schedules a restart for an extension with the given delay.
    private func scheduleRestart(for extension_: InstalledExtension, delay: TimeInterval) {
        let extensionID = extension_.uniqueIdentifier

        // Cancel any pending restart
        pendingRestarts[extensionID]?.cancel()

        let task = Task {
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return // Task was cancelled
                }
            }

            guard !Task.isCancelled else { return }

            await performRestart(for: extension_)
        }

        pendingRestarts[extensionID] = task
    }

    /// Performs the actual restart of an extension.
    private func performRestart(for extension_: InstalledExtension) async {
        guard let extensionManager else {
            Logger.error(
                "Cannot restart extension: ExtensionManager not available",
                category: Logger.extensions,
            )
            return
        }

        let extensionID = extension_.uniqueIdentifier

        do {
            // Disable and re-enable to reload
            try await extensionManager.disable(extension_)
            try await extensionManager.enable(extension_)

            // Update state
            var state = recoveryStates[extensionID] ?? RecoveryState()
            state.lastRestartAttempt = Date()
            recoveryStates[extensionID] = state

            // Log successful recovery
            let entry = ErrorLogEntry(
                extensionID: extensionID,
                extensionName: extension_.displayName,
                error: "Extension was automatically restarted after crash",
                severity: .warning,
                wasRecovered: true,
            )
            addLogEntry(entry)

            Logger.info(
                "Extension '\(extension_.displayName)' successfully restarted",
                category: Logger.extensions,
            )
        } catch {
            Logger.error(
                "Failed to restart extension '\(extension_.displayName)': \(error)",
                category: Logger.extensions,
            )

            let entry = ErrorLogEntry(
                extensionID: extensionID,
                extensionName: extension_.displayName,
                error: "Failed to restart: \(error.localizedDescription)",
                severity: .error,
            )
            addLogEntry(entry)
        }

        pendingRestarts.removeValue(forKey: extensionID)
    }

    /// Disables an extension due to repeated crashes.
    private func disableExtension(
        _ extension_: InstalledExtension,
        state: inout RecoveryState,
    ) {
        state.isDisabledDueToCrashes = true

        let entry = ErrorLogEntry(
            extensionID: extension_.uniqueIdentifier,
            extensionName: extension_.displayName,
            error: "Extension disabled due to repeated crashes (\(state.crashTimestamps.count) crashes in 1 hour)",
            severity: .crash,
        )
        addLogEntry(entry)

        Logger.warning(
            "Extension '\(extension_.displayName)' disabled due to repeated crashes",
            category: Logger.extensions,
        )

        // Disable the extension
        Task {
            guard let extensionManager else { return }
            try? await extensionManager.disable(extension_)
        }

        // Notify user
        sendCrashNotification(for: extension_)
    }

    /// Sends a system notification about extension crash.
    private func sendCrashNotification(for extension_: InstalledExtension) {
        let content = UNMutableNotificationContent()
        content.title = "Extension Disabled"
        content.body = "\"\(extension_.displayName)\" was disabled due to repeated crashes. You can re-enable it in Settings."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "extension-crash-\(extension_.uniqueIdentifier)",
            content: content,
            trigger: nil,
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Logger.error(
                    "Failed to send crash notification: \(error)",
                    category: Logger.extensions,
                )
            }
        }
    }

    // MARK: - Error Log Management

    /// Adds an entry to the error log.
    private func addLogEntry(_ entry: ErrorLogEntry) {
        errorLog.insert(entry, at: 0)

        // Trim to max entries
        if errorLog.count > maxErrorLogEntries {
            errorLog = Array(errorLog.prefix(maxErrorLogEntries))
        }
    }

    /// Clears the error log.
    func clearErrorLog() {
        errorLog.removeAll()
        Logger.info("Extension error log cleared", category: Logger.extensions)
    }

    /// Clears errors for a specific extension.
    func clearErrors(for extension_: InstalledExtension) {
        errorLog.removeAll { $0.extensionID == extension_.uniqueIdentifier }
    }

    /// Returns errors for a specific extension.
    func errors(for extension_: InstalledExtension) -> [ErrorLogEntry] {
        errorLog.filter { $0.extensionID == extension_.uniqueIdentifier }
    }

    // MARK: - State Queries

    /// Returns whether an extension was disabled due to crashes.
    func isDisabledDueToCrashes(_ extension_: InstalledExtension) -> Bool {
        recoveryStates[extension_.uniqueIdentifier]?.isDisabledDueToCrashes ?? false
    }

    /// Returns the crash count for an extension in the current window.
    func crashCount(for extension_: InstalledExtension) -> Int {
        guard let state = recoveryStates[extension_.uniqueIdentifier] else { return 0 }

        let now = Date()
        return state.crashTimestamps.count(where: {
            now.timeIntervalSince($0) < crashCountResetWindow
        })
    }

    /// Resets the crash state for an extension.
    ///
    /// Call this when a user manually re-enables an extension that was disabled.
    func resetCrashState(for extension_: InstalledExtension) {
        recoveryStates.removeValue(forKey: extension_.uniqueIdentifier)

        Logger.info(
            "Reset crash state for extension '\(extension_.displayName)'",
            category: Logger.extensions,
        )
    }

    // MARK: - Cleanup

    /// Cleans up when an extension is uninstalled.
    func extensionUninstalled(_ extension_: InstalledExtension) {
        let extensionID = extension_.uniqueIdentifier

        // Cancel any pending restarts
        pendingRestarts[extensionID]?.cancel()
        pendingRestarts.removeValue(forKey: extensionID)

        // Remove state
        recoveryStates.removeValue(forKey: extensionID)

        // Optionally clear error log entries
        // errorLog.removeAll { $0.extensionID == extensionID }
    }
}

// MARK: - Error Log Entry Extensions

extension ExtensionRecoveryManager.ErrorLogEntry {
    /// Icon for the severity level.
    var severityIcon: String {
        switch severity {
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .crash: "bolt.fill"
        }
    }

    /// Color for the severity level.
    var severityColorName: String {
        switch severity {
        case .warning: "yellow"
        case .error: "red"
        case .crash: "orange"
        }
    }
}
