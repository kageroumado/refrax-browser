import Foundation

/// Auto-lock timeout options for locked spaces.
///
/// Defines how long a space remains unlocked after authentication before
/// automatically re-locking due to inactivity.
///
/// ## Timeout Behavior
///
/// - Most timeouts are inactivity-based using system idle time (IOKit HID).
/// - `.onLoseFocus` locks immediately when the app loses focus.
/// - `.never` requires manual locking only.
///
/// ## Persistence
///
/// Stored as `Int` seconds in `Space.lockTimeoutOverride`. The default timeout
/// (5 minutes) is stored as `nil` to allow global settings changes to apply.
enum LockTimeout: Int, CaseIterable, Identifiable, Codable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case onLoseFocus = -1
    case never = 0

    var id: Int { rawValue }

    /// Human-readable description for UI display.
    var displayName: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .onLoseFocus: "When app loses focus"
        case .never: "Never (manual only)"
        }
    }

    /// Initialize from raw seconds value (for Space.lockTimeoutOverride).
    ///
    /// - Parameter seconds: The timeout in seconds, or `nil` for default (5 minutes).
    init(seconds: Int?) {
        if let seconds {
            self = LockTimeout.allCases.first { $0.rawValue == seconds } ?? .fiveMinutes
        } else {
            self = .fiveMinutes
        }
    }

    /// Whether this timeout represents the default value.
    ///
    /// Used to determine if `lockTimeoutOverride` should be stored as `nil`.
    var isDefault: Bool {
        self == .fiveMinutes
    }
}
