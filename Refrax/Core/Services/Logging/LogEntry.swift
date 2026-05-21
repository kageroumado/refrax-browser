import Foundation

/// Severity level for persistent log entries.
nonisolated enum LogLevel: String, Codable, Sendable, Comparable {
    case debug
    case info
    case warning
    case error
    case fault

    private var ordinal: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        case .fault: 4
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

/// A structured log entry written to persistent storage.
nonisolated struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
}
