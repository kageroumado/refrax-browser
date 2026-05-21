import Foundation

// MARK: - Helpers

private let weekdayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

private func dayName(for day: Int) -> String {
    (1 ... 7).contains(day) ? weekdayNames[day] : "Unknown"
}

// MARK: - RoutingCondition

/// A condition that determines when a routing rule should apply.
///
/// Conditions are evaluated against a `NavigationContext` to determine if a rule matches.
/// Multiple conditions can be combined using the `RoutingRule.conditions` array,
/// where all conditions must match (AND logic).
///
/// ## Pattern Matching
///
/// Domain and path patterns support wildcards:
/// - `*` matches any sequence of characters
/// - `*.example.com` matches any subdomain of example.com
/// - `github.com/*/issues` matches issues page of any repository
///
/// ## Examples
///
/// ```swift
/// // Match all GitHub pages
/// .domain("github.com")
///
/// // Match any subdomain of google.com
/// .domain("*.google.com")
///
/// // Match work hours
/// .timeRange(start: "09:00", end: "17:00")
///
/// // Match weekdays only
/// .dayOfWeek(.weekday)
/// ```
enum RoutingCondition: Hashable, Sendable {
    /// Matches URLs with the specified domain pattern.
    ///
    /// Supports wildcards: `*.example.com` matches subdomains.
    case domain(String)

    /// Matches URLs with the specified path pattern.
    ///
    /// Supports wildcards: `*/issues/*` matches issue paths.
    case path(String)

    /// Matches URLs where the referrer matches the pattern.
    ///
    /// Useful for routing links clicked from specific sites.
    case referrer(String)

    /// Matches navigations occurring within the specified time range.
    ///
    /// Times are in 24-hour format (e.g., "09:00", "17:30").
    /// Supports midnight wrap (e.g., start: "22:00", end: "06:00").
    case timeRange(start: String, end: String)

    /// Matches navigations on specific days of the week.
    case dayOfWeek(DaySelection)

    /// Matches when navigating from a specific space.
    case currentSpace(UUID)

    /// Matches when the URL was opened from a specific application.
    ///
    /// Uses bundle identifiers (e.g., "com.apple.mail", "com.tinyspeck.slackmacgap").
    case sourceApp(String)

    // MARK: - Nested Types

    /// Selection of days for the dayOfWeek condition.
    enum DaySelection: Codable, Hashable, Sendable {
        /// Monday through Friday
        case weekday

        /// Saturday and Sunday
        case weekend

        /// Specific day of the week (1 = Sunday, 7 = Saturday)
        case specific(Int)

        // MARK: - Codable

        private enum CodingKeys: String, CodingKey {
            case type
            case dayNumber
        }

        nonisolated init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "weekday":
                self = .weekday
            case "weekend":
                self = .weekend
            case "specific":
                let dayNumber = try container.decode(Int.self, forKey: .dayNumber)
                self = .specific(dayNumber)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown day selection type: \(type)",
                )
            }
        }

        nonisolated func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .weekday:
                try container.encode("weekday", forKey: .type)
            case .weekend:
                try container.encode("weekend", forKey: .type)
            case let .specific(dayNumber):
                try container.encode("specific", forKey: .type)
                try container.encode(dayNumber, forKey: .dayNumber)
            }
        }
    }
}

// MARK: - Codable

extension RoutingCondition: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case pattern
        case start
        case end
        case daySelection
        case spaceID
        case bundleID
    }

    private enum ConditionType: String, Codable {
        case domain
        case path
        case referrer
        case timeRange
        case dayOfWeek
        case currentSpace
        case sourceApp
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ConditionType.self, forKey: .type)

        switch type {
        case .domain:
            let pattern = try container.decode(String.self, forKey: .pattern)
            self = .domain(pattern)
        case .path:
            let pattern = try container.decode(String.self, forKey: .pattern)
            self = .path(pattern)
        case .referrer:
            let pattern = try container.decode(String.self, forKey: .pattern)
            self = .referrer(pattern)
        case .timeRange:
            let start = try container.decode(String.self, forKey: .start)
            let end = try container.decode(String.self, forKey: .end)
            self = .timeRange(start: start, end: end)
        case .dayOfWeek:
            let selection = try container.decode(DaySelection.self, forKey: .daySelection)
            self = .dayOfWeek(selection)
        case .currentSpace:
            let spaceID = try container.decode(UUID.self, forKey: .spaceID)
            self = .currentSpace(spaceID)
        case .sourceApp:
            let bundleID = try container.decode(String.self, forKey: .bundleID)
            self = .sourceApp(bundleID)
        }
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .domain(pattern):
            try container.encode(ConditionType.domain, forKey: .type)
            try container.encode(pattern, forKey: .pattern)
        case let .path(pattern):
            try container.encode(ConditionType.path, forKey: .type)
            try container.encode(pattern, forKey: .pattern)
        case let .referrer(pattern):
            try container.encode(ConditionType.referrer, forKey: .type)
            try container.encode(pattern, forKey: .pattern)
        case let .timeRange(start, end):
            try container.encode(ConditionType.timeRange, forKey: .type)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case let .dayOfWeek(selection):
            try container.encode(ConditionType.dayOfWeek, forKey: .type)
            try container.encode(selection, forKey: .daySelection)
        case let .currentSpace(spaceID):
            try container.encode(ConditionType.currentSpace, forKey: .type)
            try container.encode(spaceID, forKey: .spaceID)
        case let .sourceApp(bundleID):
            try container.encode(ConditionType.sourceApp, forKey: .type)
            try container.encode(bundleID, forKey: .bundleID)
        }
    }
}

// MARK: - Pattern Matching

extension RoutingCondition {
    /// Evaluates this condition against a navigation context.
    ///
    /// - Parameter context: The navigation context to evaluate.
    /// - Returns: `true` if the condition matches.
    nonisolated func matches(_ context: NavigationContext) -> Bool {
        switch self {
        case let .domain(pattern):
            guard let host = context.url.host else { return false }
            return PatternMatcher.matchesWildcard(host, pattern: pattern)

        case let .path(pattern):
            return PatternMatcher.matchesWildcard(context.url.path, pattern: pattern)

        case let .referrer(pattern):
            guard let referrer = context.referrer,
                  let host = referrer.host else { return false }
            return PatternMatcher.matchesWildcard(host, pattern: pattern)

        case let .timeRange(start, end):
            return matchesTimeRange(start: start, end: end, date: context.timestamp)

        case let .dayOfWeek(selection):
            return matchesDayOfWeek(selection, date: context.timestamp)

        case let .currentSpace(spaceID):
            return context.currentSpaceID == spaceID

        case let .sourceApp(bundleID):
            return context.sourceAppBundleID == bundleID
        }
    }

    private nonisolated func matchesTimeRange(start: String, end: String, date: Date) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)

        guard let hour = components.hour, let minute = components.minute else { return false }

        let currentMinutes = hour * 60 + minute
        let startMinutes = parseTimeString(start)
        let endMinutes = parseTimeString(end)

        if startMinutes <= endMinutes {
            // Normal range (e.g., 09:00 to 17:00)
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Midnight wrap (e.g., 22:00 to 06:00)
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    private nonisolated func parseTimeString(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return 0 }
        return hour * 60 + minute
    }

    private nonisolated func matchesDayOfWeek(_ selection: DaySelection, date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        switch selection {
        case .weekday:
            // 1 = Sunday, 7 = Saturday; weekdays are 2-6
            return weekday >= 2 && weekday <= 6

        case .weekend:
            return weekday == 1 || weekday == 7

        case let .specific(dayNumber):
            return weekday == dayNumber
        }
    }
}

// MARK: - Display

extension RoutingCondition {
    /// A human-readable description of this condition.
    var displayDescription: String {
        switch self {
        case let .domain(pattern):
            "Domain matches \"\(pattern)\""
        case let .path(pattern):
            "Path matches \"\(pattern)\""
        case let .referrer(pattern):
            "Referrer matches \"\(pattern)\""
        case let .timeRange(start, end):
            "Time is between \(start) and \(end)"
        case let .dayOfWeek(selection):
            switch selection {
            case .weekday: "Day is a weekday"
            case .weekend: "Day is a weekend"
            case let .specific(day): "Day is \(dayName(for: day))"
            }
        case let .currentSpace(spaceID):
            "Current space is \(spaceID.uuidString.prefix(8))..."
        case let .sourceApp(bundleID):
            "Opened from \(bundleID)"
        }
    }
}
