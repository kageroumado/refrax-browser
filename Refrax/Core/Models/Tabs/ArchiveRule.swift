import Foundation
import SwiftData

/// A user-defined rule for automatically archiving tabs.
///
/// Archive rules allow users to automatically clean up tabs based on criteria like:
/// - Inactivity duration (tabs not accessed for N days)
/// - Tab count limits (keep max N tabs, archive oldest when exceeded)
///
/// Rules can be scoped to specific domains (e.g., `*.reddit.com`) or spaces.
/// When multiple rules match a tab, they are evaluated in priority order.
///
/// ## Rule Types
///
/// - `.inactivity`: Archives tabs that haven't been accessed for a specified number of days.
/// - `.tabCountLimit`: Archives the oldest tabs when the count exceeds a limit.
///
/// ## Domain Patterns
///
/// Domain patterns support wildcards for subdomain matching:
/// - `"*.reddit.com"` matches `reddit.com`, `www.reddit.com`, `old.reddit.com`
/// - `"example.com"` matches only `example.com` exactly
/// - `nil` matches all domains
///
/// ## Example Usage
///
/// ```swift
/// // Archive Reddit tabs after 1 day of inactivity
/// let socialRule = ArchiveRule(
///     name: "Social Media Cleanup",
///     ruleType: .inactivity,
///     domainPattern: "*.reddit.com",
///     inactivityDays: 1
/// )
///
/// // Keep max 20 tabs in Work space
/// let workLimitRule = ArchiveRule(
///     name: "Work Space Limit",
///     ruleType: .tabCountLimit,
///     spaceID: workSpace.id,
///     maxTabCount: 20
/// )
/// ```
@Model
final class ArchiveRule {
    #Index<ArchiveRule>([\.isEnabled], [\.priority])

    // MARK: - Identity

    /// Unique identifier for this rule.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID

    /// User-visible name for the rule.
    var name: String

    // MARK: - Configuration

    /// The type of rule (inactivity or tab count limit).
    ///
    /// Stored as raw value for persistence.
    var ruleTypeRaw: String

    /// Domain pattern to match, or `nil` to match all domains.
    ///
    /// Supports wildcard patterns like `"*.reddit.com"`.
    var domainPattern: String?

    /// Whether this rule is currently active.
    var isEnabled: Bool

    /// Evaluation priority (higher values evaluated first).
    ///
    /// When multiple rules could apply to a tab, higher-priority rules
    /// are checked first.
    var priority: Int

    /// Space ID to scope this rule to, or `nil` for all spaces.
    var spaceID: UUID?

    // MARK: - Type-Specific Configuration

    /// Days of inactivity before archiving (for `.inactivity` type).
    ///
    /// Only used when `ruleType == .inactivity`.
    var inactivityDays: Int?

    /// Maximum tab count before archiving oldest (for `.tabCountLimit` type).
    ///
    /// Only used when `ruleType == .tabCountLimit`.
    var maxTabCount: Int?

    // MARK: - Computed Properties

    /// The type of this archive rule.
    var ruleType: ArchiveRuleType {
        get { ArchiveRuleType(rawValue: ruleTypeRaw) ?? .inactivity }
        set { ruleTypeRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    /// Creates a new archive rule.
    ///
    /// - Parameters:
    ///   - name: User-visible name for the rule.
    ///   - ruleType: The type of rule (inactivity or tab count limit).
    ///   - domainPattern: Domain pattern to match, or `nil` for all domains.
    ///   - isEnabled: Whether the rule is active. Defaults to `true`.
    ///   - priority: Evaluation priority. Defaults to `0`.
    ///   - spaceID: Space to scope to, or `nil` for all spaces.
    ///   - inactivityDays: Days of inactivity (for `.inactivity` type).
    ///   - maxTabCount: Maximum tab count (for `.tabCountLimit` type).
    init(
        name: String,
        ruleType: ArchiveRuleType,
        domainPattern: String? = nil,
        isEnabled: Bool = true,
        priority: Int = 0,
        spaceID: UUID? = nil,
        inactivityDays: Int? = nil,
        maxTabCount: Int? = nil,
    ) {
        self.id = UUID()
        self.name = name
        self.ruleTypeRaw = ruleType.rawValue
        self.domainPattern = domainPattern
        self.isEnabled = isEnabled
        self.priority = priority
        self.spaceID = spaceID
        self.inactivityDays = inactivityDays
        self.maxTabCount = maxTabCount
    }

    // MARK: - Matching

    /// Returns whether this rule applies to the given space.
    ///
    /// A rule applies if it has no space scope, or if its scope matches the space.
    func applies(to space: Space) -> Bool {
        spaceID == nil || spaceID == space.id
    }

    // MARK: - Display

    /// Human-readable description of what this rule does.
    var ruleDescription: String {
        let target = domainPattern ?? "all tabs"

        switch ruleType {
        case .inactivity:
            let days = inactivityDays ?? 3
            let dayWord = days == 1 ? "day" : "days"
            return "\(target) → \(days) \(dayWord) inactive"
        case .tabCountLimit:
            let count = maxTabCount ?? 50
            return "\(target) → max \(count) tabs"
        }
    }
}

// MARK: - Archive Rule Type

/// The type of archive rule.
enum ArchiveRuleType: String, Codable, CaseIterable, Sendable {
    /// Archives tabs after N days of inactivity.
    case inactivity

    /// Archives oldest tabs when count exceeds N.
    case tabCountLimit

    /// Display name for the rule type.
    var displayName: String {
        switch self {
        case .inactivity:
            String(localized: "Inactivity")
        case .tabCountLimit:
            String(localized: "Tab Count Limit")
        }
    }

    /// Description of what this rule type does.
    var typeDescription: String {
        switch self {
        case .inactivity:
            String(localized: "Archive tabs not accessed for a specified number of days")
        case .tabCountLimit:
            String(localized: "Archive oldest tabs when count exceeds a limit")
        }
    }
}
