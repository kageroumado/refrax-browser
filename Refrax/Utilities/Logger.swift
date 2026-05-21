import Foundation
import OSLog

/// Centralized logging utility using OSLog for categorized logging.
///
/// Log levels `warning`, `error`, and `fault` are automatically persisted
/// to disk via ``PersistentLogWriter`` for inclusion in feedback reports.
enum Logger: @unchecked Sendable {
    // MARK: - Log Categories

    nonisolated static let navigation = OSLog(subsystem: Constants.App.bundleID, category: "navigation")
    nonisolated static let tabs = OSLog(subsystem: Constants.App.bundleID, category: "tabs")
    nonisolated static let webview = OSLog(subsystem: Constants.App.bundleID, category: "webview")
    nonisolated static let window = OSLog(subsystem: Constants.App.bundleID, category: "window")
    nonisolated static let ui = OSLog(subsystem: Constants.App.bundleID, category: "ui")
    nonisolated static let data = OSLog(subsystem: Constants.App.bundleID, category: "data")
    nonisolated static let network = OSLog(subsystem: Constants.App.bundleID, category: "network")
    nonisolated static let autoFill = OSLog(subsystem: Constants.App.bundleID, category: "autofill")
    nonisolated static let downloads = OSLog(subsystem: Constants.App.bundleID, category: "downloads")
    nonisolated static let extensions = OSLog(subsystem: Constants.App.bundleID, category: "extensions")
    nonisolated static let storage = OSLog(subsystem: Constants.App.bundleID, category: "storage")
    nonisolated static let security = OSLog(subsystem: Constants.App.bundleID, category: "security")
    nonisolated static let calendar = OSLog(subsystem: Constants.App.bundleID, category: "calendar")
    nonisolated static let clipboard = OSLog(subsystem: Constants.App.bundleID, category: "clipboard")
    nonisolated static let agent = OSLog(subsystem: Constants.App.bundleID, category: "agent")
    nonisolated static let sync = OSLog(subsystem: Constants.App.bundleID, category: "sync")
    nonisolated static let system = OSLog(subsystem: Constants.App.bundleID, category: "system")
    nonisolated static let updates = OSLog(subsystem: Constants.App.bundleID, category: "updates")
    nonisolated static let lightboard = OSLog(subsystem: Constants.App.bundleID, category: "lightboard")

    // MARK: - Logging Methods

    /// Log a message with specified category and type
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (default: .default)
    ///   - type: The log type (default: .default)
    nonisolated static func log(_ message: String, category: OSLog = .default, type: OSLogType = .default) {
        os_log("%{public}@", log: category, type: type, message)
    }

    /// Log a debug message
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category
    nonisolated static func debug(_ message: String, category: OSLog = .default) {
        #if DEBUG
            os_log("%{public}@", log: category, type: .debug, message)
        #endif
    }

    /// Log an info message
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category
    nonisolated static func info(_ message: String, category: OSLog = .default) {
        os_log("%{public}@", log: category, type: .info, message)
    }

    /// Log an error message
    /// - Parameters:
    ///   - message: The error message
    ///   - category: The log category
    nonisolated static func error(_ message: String, category: OSLog = .default) {
        os_log("%{public}@", log: category, type: .error, message)
        persist(message, level: .error, category: category)
    }

    /// Log a fault message
    /// - Parameters:
    ///   - message: The fault message
    ///   - category: The log category
    nonisolated static func fault(_ message: String, category: OSLog = .default) {
        os_log("%{public}@", log: category, type: .fault, message)
        persist(message, level: .fault, category: category)
    }

    /// Log a warning message
    /// - Parameters:
    ///   - message: The warning message
    ///   - category: The log category
    nonisolated static func warning(_ message: String, category: OSLog = .default) {
        os_log("%{public}@", log: category, type: .default, message)
        persist(message, level: .warning, category: category)
    }

    /// Log an error object
    /// - Parameters:
    ///   - error: The error object
    ///   - category: The log category
    nonisolated static func error(_ error: any Error, category: OSLog = .default) {
        os_log("%{public}@", log: category, type: .error, error.localizedDescription)
        persist(error.localizedDescription, level: .error, category: category)
    }

    // MARK: - Persistent Log Writer

    /// Writes a log entry to the persistent log file.
    ///
    /// Warning, error, and fault messages are always persisted to disk
    /// for inclusion in feedback reports and crash diagnostics.
    private nonisolated static func persist(
        _ message: String,
        level: LogLevel,
        category: OSLog,
    ) {
        let name = categoryName(for: category)
        let entry = LogEntry(
            timestamp: .now,
            level: level,
            category: name,
            message: message,
        )
        Task { await PersistentLogWriter.shared.write(entry) }
    }

    /// Resolves an OSLog instance back to its category name string.
    private nonisolated static func categoryName(for log: OSLog) -> String {
        if log === navigation { return "navigation" }
        if log === tabs { return "tabs" }
        if log === webview { return "webview" }
        if log === window { return "window" }
        if log === ui { return "ui" }
        if log === data { return "data" }
        if log === network { return "network" }
        if log === autoFill { return "autofill" }
        if log === downloads { return "downloads" }
        if log === extensions { return "extensions" }
        if log === storage { return "storage" }
        if log === security { return "security" }
        if log === calendar { return "calendar" }
        if log === clipboard { return "clipboard" }
        if log === agent { return "agent" }
        if log === system { return "system" }
        return "default"
    }
}
