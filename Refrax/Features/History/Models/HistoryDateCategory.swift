import Foundation

/// Represents a date-based category for filtering history entries in the sidebar.
///
/// Supports both predefined periods (Today, Yesterday, etc.) and specific months.
/// Categories are hashable and identifiable for use in SwiftUI selection.
enum HistoryDateCategory: Hashable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case month(year: Int, month: Int) // Specific month like "November 2025"

    var id: String {
        switch self {
        case .today: "today"
        case .yesterday: "yesterday"
        case .thisWeek: "thisWeek"
        case .thisMonth: "thisMonth"
        case let .month(year, month): "month-\(year)-\(month)"
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case let .month(year, month):
            let components = DateComponents(year: year, month: month, day: 1)
            guard let date = Calendar.current.date(from: components) else {
                return "\(month)/\(year)"
            }
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    /// Icon for sidebar display.
    var icon: String {
        switch self {
        case .today: "clock"
        case .yesterday: "clock.arrow.circlepath"
        case .thisWeek: "calendar"
        case .thisMonth: "calendar.circle"
        case .month: "calendar.badge.clock"
        }
    }

    /// The date range this category represents.
    var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return start ... end

        case .yesterday:
            let todayStart = calendar.startOfDay(for: now)
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            return yesterdayStart ... todayStart

        case .thisWeek:
            let todayStart = calendar.startOfDay(for: now)
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            // Exclude today and yesterday (they have their own categories)
            let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: todayStart)!
            // If we're early in the week (1-2 days in), this range will be degenerate (single point)
            // which effectively matches nothing - that's the intended behavior
            return weekStart ... max(weekStart, dayBeforeYesterday)

        case .thisMonth:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            // Exclude this week (it has its own category)
            let dayBeforeWeekStart = calendar.date(byAdding: .day, value: -1, to: weekStart)!
            return monthStart ... max(monthStart, dayBeforeWeekStart)

        case let .month(year, month):
            var components = DateComponents(year: year, month: month, day: 1)
            guard let monthStart = calendar.date(from: components) else {
                return now ... now
            }
            components.month = month + 1
            guard let nextMonthStart = calendar.date(from: components) else {
                return monthStart ... monthStart
            }
            let monthEnd = calendar.date(byAdding: .second, value: -1, to: nextMonthStart)!
            return monthStart ... monthEnd
        }
    }

    /// Check if a date falls within this category.
    func contains(_ date: Date) -> Bool {
        dateRange.contains(date)
    }

    /// Sort order for sidebar display (most recent first).
    var sortOrder: Int {
        switch self {
        case .today: 0
        case .yesterday: 1
        case .thisWeek: 2
        case .thisMonth: 3
        case let .month(year, month):
            // Negative so newer months sort first
            -(year * 12 + month)
        }
    }

    /// Creates categories for all months that have history entries.
    ///
    /// Excludes the current month (covered by predefined categories).
    static func monthCategories(from entries: [Date]) -> [HistoryDateCategory] {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        var monthsWithEntries: Set<String> = []

        for date in entries {
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)

            // Skip current month (covered by Today/Yesterday/ThisWeek/ThisMonth)
            if year == currentYear, month == currentMonth {
                continue
            }

            monthsWithEntries.insert("\(year)-\(month)")
        }

        return monthsWithEntries.compactMap { key -> HistoryDateCategory? in
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1])
            else {
                return nil
            }
            return .month(year: year, month: month)
        }
        .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// All predefined categories in display order.
    static let predefined: [HistoryDateCategory] = [.today, .yesterday, .thisWeek, .thisMonth]
}
