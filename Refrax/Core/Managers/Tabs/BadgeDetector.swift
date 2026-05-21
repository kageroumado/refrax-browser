import Foundation

/// Detects notification count patterns in page titles for badge indicators.
///
/// Many web applications update their tab titles to show unread counts:
/// - "(3) Gmail" - New emails
/// - "[5] Slack" - Unread messages
/// - "(7) Discord" - Notifications
///
/// This detector identifies these patterns to automatically mark tabs as unread.
enum BadgeDetector {
    /// Detection patterns in priority order.
    ///
    /// Patterns are ordered by commonality to optimize matching.
    private static let patterns: [NSRegularExpression] = [
        // (n) at start: "(3) Gmail"
        try! NSRegularExpression(pattern: #"^\((\d+)\)"#),
        // [n] at start: "[5] Slack"
        try! NSRegularExpression(pattern: #"^\[(\d+)\]"#),
        // n: at start: "3: Twitter"
        try! NSRegularExpression(pattern: #"^(\d+):"#),
        // (n) at end: "Gmail (3)"
        try! NSRegularExpression(pattern: #"\((\d+)\)$"#),
        // [n] at end: "Slack [5]"
        try! NSRegularExpression(pattern: #"\[(\d+)\]$"#),
    ]

    /// Returns the notification count if a badge pattern is detected.
    ///
    /// - Parameter title: The page title to scan.
    /// - Returns: The notification count if detected and greater than 0, nil otherwise.
    static func detectBadge(in title: String) -> Int? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return nil }

        let range = NSRange(trimmedTitle.startIndex..., in: trimmedTitle)

        for pattern in patterns {
            if let match = pattern.firstMatch(in: trimmedTitle, range: range),
               let countRange = Range(match.range(at: 1), in: trimmedTitle),
               let count = Int(trimmedTitle[countRange]),
               count > 0 {
                return count
            }
        }

        return nil
    }

    /// Checks if a title contains a badge pattern.
    ///
    /// - Parameter title: The page title to check.
    /// - Returns: `true` if a badge pattern with count > 0 is detected.
    static func hasBadge(in title: String) -> Bool {
        detectBadge(in: title) != nil
    }
}
