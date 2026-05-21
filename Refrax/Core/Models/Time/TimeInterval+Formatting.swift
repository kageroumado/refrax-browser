import Foundation

extension TimeInterval {
    /// Formats this time interval as a human-readable duration.
    ///
    /// Examples:
    /// - 45 seconds → "< 1m"
    /// - 1,800 seconds → "30m"
    /// - 5,400 seconds → "1h 30m"
    /// - 7,200 seconds → "2h 0m"
    nonisolated var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }

    /// Formats this time interval as a short duration for compact display.
    ///
    /// Examples:
    /// - 1,800 seconds → "30m"
    /// - 3,600 seconds → "1h"
    /// - 5,400 seconds → "1h 30m"
    nonisolated var shortDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
