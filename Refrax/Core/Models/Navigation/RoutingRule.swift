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

    /// The conditions that must all be met for this rule to apply.
    ///
    /// All conditions must match (AND logic). For OR logic, create multiple rules.
    var conditions: [RoutingCondition]

    /// The action to perform when all conditions match.
    var action: RoutingAction

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
        self.conditions = conditions
        self.action = action
        self.priority = priority
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Evaluates this rule against a navigation context.
    ///
    /// - Parameter context: The navigation context to evaluate.
    /// - Returns: `true` if all conditions match.
    nonisolated func matches(_ context: NavigationContext) -> Bool {
        guard isEnabled else { return false }

        // All conditions must match (AND logic)
        for condition in conditions {
            if !condition.matches(context) {
                return false
            }
        }

        return true
    }

    /// Updates the modification timestamp to now.
    func markModified() {
        modifiedAt = Date()
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
