import Foundation

// MARK: - Snapshot Date Formatter

/// Utility for formatting snapshot dates with context-aware labels.
///
/// Formatting styles:
/// - Today → "Today"
/// - Yesterday → "Yesterday"
/// - This week → Day name ("Monday", "Tuesday")
/// - This year → "Jan 9", "Feb 14"
/// - Previous years → "Jan 9, 2025"
enum SnapshotDateFormatter {
    /// The style of date formatting to apply.
    enum Style {
        /// For folder list view (e.g., "Today", "Yesterday", "Monday")
        case folder
        /// For header when viewing a specific date
        case header
    }

    /// Formats a date according to the specified style.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - style: The formatting style to use.
    /// - Returns: A formatted date string.
    static func formatDate(_ date: Date, style _: Style) -> String {
        let calendar = Calendar.current
        let now = Date()

        // Today
        if calendar.isDateInToday(date) {
            return "Today"
        }

        // Yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        // This week - use day name
        if isWithinLastWeek(date, from: now, calendar: calendar) {
            return date.formatted(.dateTime.weekday(.wide))
        }

        // This year - use "Jan 9" format
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }

        // Previous years - use "Jan 9, 2025" format
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Checks if a date is within the last 7 days (excluding today and yesterday).
    private static func isWithinLastWeek(_ date: Date, from referenceDate: Date, calendar: Calendar) -> Bool {
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: referenceDate) else {
            return false
        }

        // Date should be after a week ago and before yesterday
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
              let dayBeforeYesterday = calendar.date(byAdding: .day, value: -1, to: yesterday) else {
            return false
        }

        return date >= weekAgo && date <= calendar.startOfDay(for: dayBeforeYesterday)
    }
}
