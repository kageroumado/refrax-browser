import Foundation
import SwiftData

/// Settings for handling URLs opened from external applications.
///
/// When another app opens a URL in Refrax (via default browser, open command, or
/// URL scheme), these settings control where and how the URL is displayed.
///
/// ## External URL Sources
///
/// - System default browser (clicking links in Mail, Notes, etc.)
/// - AppleScript/shell `open` command
/// - Other apps using `NSWorkspace.open(_:)`
/// - URL scheme handlers (http/https registered to Refrax)
///
/// ## Behavior Options
///
/// 1. **Window behavior**: New window, existing window, or Glimpse window
/// 2. **Space routing**: Specific space, current space, or rule-based
/// 3. **URL-specific rules**: Different handling for different URL patterns
///
/// ## Integration
///
/// External URL handling is triggered in `WindowManager.openExternalURL(_:)`.
/// The flow is:
///
/// ```
/// AppDelegate.handleGetURLEvent
///     ↓
/// WindowManager.openExternalURL
///     ↓
/// ExternalURLSettings.resolve → ExternalURLAction
///     ↓
/// Execute action (new tab, Glimpse window, etc.)
/// ```
@Model
final class ExternalURLSettings {
    // MARK: - Identity

    /// Stable identifier for sync.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    // MARK: - Global Settings

    /// Master toggle for custom external URL handling.
    ///
    /// When disabled, all external URLs open in the current window's active space
    /// using default behavior.
    var enableCustomHandling: Bool = false

    /// Default behavior when no specific rule matches.
    var defaultBehaviorRaw: String = ExternalURLBehavior.openInCurrentSpace.rawValue

    /// Default behavior when no rule matches.
    var defaultBehavior: ExternalURLBehavior {
        get { ExternalURLBehavior(rawValue: defaultBehaviorRaw) ?? .openInCurrentSpace }
        set { defaultBehaviorRaw = newValue.rawValue }
    }

    /// Target space ID for when default behavior is `.openInSpecificSpace`.
    var defaultTargetSpaceID: UUID?

    /// Whether to activate Refrax when receiving external URLs.
    ///
    /// When true, Refrax comes to the foreground. When false, the URL loads
    /// in the background.
    var activateOnExternalURL: Bool = true

    /// Whether to show a notification when receiving external URLs in background.
    ///
    /// Only applies when `activateOnExternalURL` is false.
    var notifyOnBackgroundOpen: Bool = true

    // MARK: - Rules

    /// User-defined rules for handling specific URL patterns.
    ///
    /// Rules are evaluated in order; first match wins.
    @Relationship(deleteRule: .cascade, inverse: \ExternalURLRule.settings)
    var rules: [ExternalURLRule] = []

    // MARK: - Source App Rules

    /// Rules based on the source application that opened the URL.
    ///
    /// Allows different behavior for links clicked in Mail vs Slack, for example.
    @Relationship(deleteRule: .cascade, inverse: \SourceAppRule.settings)
    var sourceAppRules: [SourceAppRule] = []

    // MARK: - Initialization

    init() {}

    // MARK: - Resolution

    /// Resolves how to handle an external URL.
    ///
    /// Evaluates rules in order and returns the appropriate action.
    ///
    /// - Parameters:
    ///   - url: The URL to handle.
    ///   - sourceAppBundleID: The bundle ID of the app that opened the URL, if known.
    /// - Returns: The action to take for this URL.
    func resolve(url: URL, sourceAppBundleID: String? = nil) -> ExternalURLAction {
        guard enableCustomHandling else {
            return .default
        }

        // Check source app rules first (more specific)
        if let bundleID = sourceAppBundleID {
            let matchingSourceRule = sourceAppRules
                .lazy
                .filter(\.isEnabled)
                .sorted { $0.order < $1.order }
                .first { $0.matches(bundleID: bundleID) }

            if let rule = matchingSourceRule {
                return rule.action
            }
        }

        // Check URL pattern rules
        let matchingRule = rules
            .lazy
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
            .first { $0.matches(url) }

        if let rule = matchingRule {
            return rule.action
        }

        // Fall back to default behavior
        return defaultAction
    }

    /// The action derived from the default behavior setting.
    private var defaultAction: ExternalURLAction {
        switch defaultBehavior {
        case .openInCurrentSpace:
            .openInCurrentSpace
        case .openInGlimpse:
            .openInGlimpse
        case .openInSpecificSpace:
            defaultTargetSpaceID.map { .openInSpace($0) } ?? .openInCurrentSpace
        }
    }
}

// MARK: - External URL Behavior

/// Default behaviors for handling external URLs.
enum ExternalURLBehavior: String, Codable, CaseIterable, Sendable {
    /// Create a new tab in the frontmost window's active space.
    case openInCurrentSpace = "currentSpace"

    /// Open in a Glimpse window (lightweight popup).
    case openInGlimpse = "glimpse"

    /// Open in a specific space (requires `defaultTargetSpaceID`).
    case openInSpecificSpace = "specificSpace"

    var displayName: String {
        switch self {
        case .openInCurrentSpace:
            "Current Space"
        case .openInGlimpse:
            "Glimpse"
        case .openInSpecificSpace:
            "Specific Space"
        }
    }

    /// Human-readable description of this behavior.
    var displayDescription: String {
        switch self {
        case .openInCurrentSpace:
            "Create a new tab in the frontmost window's active space"
        case .openInGlimpse:
            "Open in a lightweight Glimpse window"
        case .openInSpecificSpace:
            "Always open in a designated space"
        }
    }
}

// MARK: - External URL Action

/// Actions that can be taken when handling an external URL.
nonisolated enum ExternalURLAction: Equatable, Sendable {
    /// Use default browser behavior.
    case `default`

    /// Open in the current window's active space.
    case openInCurrentSpace

    /// Open in a Glimpse window.
    case openInGlimpse

    /// Open in a specific space.
    case openInSpace(UUID)

    /// Open in a specific space and group.
    case openInGroup(spaceID: UUID, groupID: UUID)

    /// Block the URL (don't open).
    case block

    // MARK: - Raw Value Encoding

    /// Encodes the action for storage in SwiftData model properties.
    nonisolated func encode() -> (rawValue: String, targetSpaceID: UUID?, targetGroupID: UUID?) {
        switch self {
        case .default:
            ("default", nil, nil)
        case .openInCurrentSpace:
            ("currentSpace", nil, nil)
        case .openInGlimpse:
            ("glimpse", nil, nil)
        case let .openInSpace(spaceID):
            ("space", spaceID, nil)
        case let .openInGroup(spaceID, groupID):
            ("group", spaceID, groupID)
        case .block:
            ("block", nil, nil)
        }
    }

    /// Decodes an action from stored raw values.
    nonisolated static func decode(
        from rawValue: String,
        targetSpaceID: UUID?,
        targetGroupID: UUID?,
    ) -> ExternalURLAction {
        switch rawValue {
        case "default":
            .default
        case "currentSpace":
            .openInCurrentSpace
        case "glimpse":
            .openInGlimpse
        case "space":
            if let spaceID = targetSpaceID {
                .openInSpace(spaceID)
            } else {
                .openInCurrentSpace
            }
        case "group":
            if let spaceID = targetSpaceID, let groupID = targetGroupID {
                .openInGroup(spaceID: spaceID, groupID: groupID)
            } else {
                .openInCurrentSpace
            }
        case "block":
            .block
        default:
            .openInCurrentSpace
        }
    }

    /// A human-readable description of this action.
    nonisolated var description: String {
        switch self {
        case .default: "Default behavior"
        case .openInCurrentSpace: "Open in current space"
        case .openInGlimpse: "Open in Glimpse window"
        case .openInSpace: "Open in specific space"
        case .openInGroup: "Open in specific group"
        case .block: "Block URL"
        }
    }
}
