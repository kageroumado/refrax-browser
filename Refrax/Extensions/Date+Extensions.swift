import Foundation

extension Date {
    /// Formats the date relative to now (e.g., "5 minutes ago", "2 hours ago").
    var relativeFormatted: String {
        formatted(.relative(presentation: .numeric, unitsStyle: .wide))
    }
}
