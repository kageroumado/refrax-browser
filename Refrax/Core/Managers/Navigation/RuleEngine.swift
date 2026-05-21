import Foundation
import SwiftData

/// Evaluates navigation contexts against routing rules.
///
/// The engine loads enabled rules from the database, orders them by priority,
/// and evaluates them against navigation contexts using first-match-wins semantics.
///
/// ## Usage
///
/// ```swift
/// let engine = RuleEngine(modelContext: context)
///
/// let context = NavigationContext(url: url, referrer: referrer, ...)
/// if let action = engine.matchingAction(for: context) {
///     // Execute the matched action
///     executor.execute(action, for: url)
/// } else {
///     // Use default navigation behavior
/// }
/// ```
///
/// ## Performance
///
/// Rules are cached in memory and reloaded when `reloadRules()` is called.
/// The cache should be invalidated when rules are added, modified, or deleted.
@Observable
final class RuleEngine {
    // MARK: - Properties

    /// Cached rules ordered by priority (descending).
    private var rules: [RoutingRule] = []

    /// The model context for fetching rules.
    private let modelContext: ModelContext

    /// Whether rules have been loaded.
    private var isLoaded = false

    // MARK: - Initialization

    /// Creates a rule engine.
    ///
    /// - Parameter modelContext: The SwiftData context for fetching rules.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Rule Loading

    /// Reloads rules from the database.
    ///
    /// Call this when rules are added, modified, or deleted.
    func reloadRules() {
        do {
            rules = try modelContext.fetch(RoutingRule.enabledByPriority)
            isLoaded = true
            Logger.debug("Loaded \(rules.count) routing rules", category: Logger.tabs)
        } catch {
            Logger.error("Failed to load routing rules: \(error)", category: Logger.tabs)
            rules = []
        }
    }

    /// Ensures rules are loaded.
    private func ensureLoaded() {
        if !isLoaded {
            reloadRules()
        }
    }

    // MARK: - Evaluation

    /// Returns the action from the first rule matching the given navigation context.
    ///
    /// Uses first-match-wins semantics: the first rule (by priority) whose
    /// conditions all match is returned.
    ///
    /// - Parameter context: The navigation context to evaluate.
    /// - Returns: The action from the first matching rule, or `nil` if no rules match.
    func matchingAction(for context: NavigationContext) -> RoutingAction? {
        ensureLoaded()

        for rule in rules {
            if rule.matches(context) {
                Logger.debug("Rule '\(rule.name)' matched for \(context.url)", category: Logger.tabs)
                return rule.action
            }
        }

        return nil
    }

    /// Evaluates a navigation context and returns all matching rules.
    ///
    /// Useful for debugging or showing the user which rules could apply.
    ///
    /// - Parameter context: The navigation context to evaluate.
    /// - Returns: All rules whose conditions match, ordered by priority.
    func allMatchingRules(for context: NavigationContext) -> [RoutingRule] {
        ensureLoaded()
        return rules.filter { $0.matches(context) }
    }

    /// Returns the first rule matching the given URL without actually navigating.
    ///
    /// Useful for the rule testing UI.
    ///
    /// - Parameters:
    ///   - url: The URL to test.
    ///   - referrer: Optional referrer URL.
    ///   - currentSpaceID: Optional current space ID.
    ///   - sourceAppBundleID: Optional source app bundle ID.
    /// - Returns: The matching rule and action, or `nil` if no rules match.
    func matchingRule(
        for url: URL,
        referrer: URL? = nil,
        currentSpaceID: UUID? = nil,
        sourceAppBundleID: String? = nil,
    ) -> (rule: RoutingRule, action: RoutingAction)? {
        let context = NavigationContext(
            url: url,
            referrer: referrer,
            currentSpaceID: currentSpaceID,
            sourceAppBundleID: sourceAppBundleID,
        )

        ensureLoaded()

        for rule in rules {
            if rule.matches(context) {
                return (rule, rule.action)
            }
        }

        return nil
    }

    // MARK: - Rule Access

    /// The number of enabled rules.
    var ruleCount: Int {
        ensureLoaded()
        return rules.count
    }

    /// Whether any routing rules are configured.
    var hasRules: Bool {
        ensureLoaded()
        return !rules.isEmpty
    }
}
