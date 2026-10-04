import Foundation
import SwiftData

/// A user-defined rule for routing URLs to specific destinations.
///
/// Routing rules allow users to automatically direct URLs to specific spaces,
/// groups, or Glimpse windows based on conditions like domain, time, or source app.
///
/// ## Evaluation Order
///
/// Rules are evaluated in priority order (higher priority first).
/// The first rule whose conditions all match is applied.
/// If no rules match, the default navigation behavior is used.
///
/// ## Examples
///
/// ```swift
/// // Route all GitHub URLs to a "Development" space
/// let rule = RoutingRule(
///     name: "GitHub to Dev",
///     conditions: [.domain("github.com")],
///     action: .openInSpace(devSpaceID)
/// )
///
/// // Route work apps during business hours
/// let workRule = RoutingRule(
///     name: "Work Hours",
///     conditions: [
///         .domain("*.mycompany.com"),
///         .timeRange(start: "09:00", end: "17:00"),
///         .dayOfWeek(.weekday)
///     ],
///     action: .openInSpace(workSpaceID)
/// )
/// ```
@Model
final class RoutingRule {
    /// Unique identifier for the rule.
    @Attribute(.unique, .preserveValueOnDeletion) var id: UUID

    /// Human-readable name for the rule.
    var name: String

    /// JSON encoding of ``conditions``, identical to the `conditionsJSON` field of the CloudKit record.
    ///
    /// Stored as a string because SwiftData persists a `Codable` enum as a composite attribute
    /// whose schema it reflects from the enum's cases. `RoutingCondition`'s discriminated
    /// encoding writes a `type` key that schema lacks, and SwiftData traps on save.
    var conditionsJSON: String = "[]"

    /// JSON encoding of ``action``, identical to the `actionJSON` field of the CloudKit record.
    ///
    /// Stored as a string for the same reason as ``conditionsJSON``.
    var actionJSON: String = ""

    /// Priority for rule ordering (higher values = higher priority).
    ///
    /// When multiple rules could match, the highest priority rule wins.
    var priority: Int

    /// Whether this rule is currently active.
    ///
    /// Disabled rules are skipped during evaluation.
    var isEnabled: Bool

    /// When this rule was created.
    var createdAt: Date

    /// When this rule was last modified.
    var modifiedAt: Date

    /// Creates a new routing rule.
    ///
    /// - Parameters:
    ///   - name: Human-readable name for the rule.
    ///   - conditions: Conditions that must all match.
    ///   - action: Action to perform when matched.
    ///   - priority: Priority for ordering (default: 0).
    ///   - isEnabled: Whether the rule is active (default: true).
    init(
        name: String,
        conditions: [RoutingCondition],
        action: RoutingAction,
        priority: Int = 0,
        isEnabled: Bool = true,
    ) {
        self.id = UUID()
        self.name = name
        self.conditionsJSON = Self.encodeJSON(conditions)
        self.actionJSON = Self.encodeJSON(action)
        self.priority = priority
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Evaluates this rule against a navigation context.
    ///
    /// A rule whose stored conditions fail to decode never matches, so it cannot widen into a
    /// rule with no conditions that matches every URL.
    ///
    /// - Parameter context: The navigation context to evaluate.
    /// - Returns: `true` if all conditions match.
    nonisolated func matches(_ context: NavigationContext) -> Bool {
        guard isEnabled, let conditions = decodedConditions else { return false }
        return conditions.allSatisfy { $0.matches(context) }
    }

    /// Updates the modification timestamp to now.
    func markModified() {
        modifiedAt = Date()
    }
}

// MARK: - Conditions & Action

extension RoutingRule {
    /// The conditions that must all be met for this rule to apply.
    ///
    /// All conditions must match (AND logic). For OR logic, create multiple rules.
    /// Empty when ``conditionsJSON`` fails to decode.
    nonisolated var conditions: [RoutingCondition] {
        get { decodedConditions ?? [] }
        set { conditionsJSON = Self.encodeJSON(newValue) }
    }

    /// The action to perform when all conditions match.
    ///
    /// ``RoutingAction/openInBackground`` when ``actionJSON`` fails to decode, the same
    /// fallback sync applies to an undecodable record.
    nonisolated var action: RoutingAction {
        get { Self.decodeJSON(RoutingAction.self, from: actionJSON) ?? .openInBackground }
        set { actionJSON = Self.encodeJSON(newValue) }
    }

    private nonisolated var decodedConditions: [RoutingCondition]? {
        Self.decodeJSON([RoutingCondition].self, from: conditionsJSON)
    }

    private nonisolated static func encodeJSON(_ value: some Encodable) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated static func decodeJSON<Value: Decodable>(_ type: Value.Type, from json: String) -> Value? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

// MARK: - Predicate Helpers

extension RoutingRule {
    /// Predicate for fetching enabled rules ordered by priority.
    static var enabledByPriority: FetchDescriptor<RoutingRule> {
        FetchDescriptor<RoutingRule>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\.priority, order: .reverse)],
        )
    }

    /// Predicate for fetching all rules ordered by priority.
    static var allByPriority: FetchDescriptor<RoutingRule> {
        FetchDescriptor<RoutingRule>(
            sortBy: [SortDescriptor(\.priority, order: .reverse)],
        )
    }
}
