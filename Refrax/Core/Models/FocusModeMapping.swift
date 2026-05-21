import Foundation
import SwiftData

/// Maps a macOS Focus Mode to browser behavior.
///
/// When a Focus Mode activates, Refrax can automatically switch all windows
/// to a mapped space, block distracting domains, blur content, and suppress
/// notifications.
///
/// ## Usage
///
/// ```swift
/// // Create mapping for "Work" Focus Mode
/// let mapping = FocusModeMapping(
///     focusIdentifier: "com.apple.focus.work",
///     focusDisplayName: "Work"
/// )
/// mapping.targetSpaceID = workSpace.id
/// mapping.restrictedDomains = ["reddit.com", "twitter.com"]
/// ```
@Model
final class FocusModeMapping {
    // MARK: - Identity

    /// Unique identifier for this mapping.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID

    /// System identifier for the Focus Mode (e.g., "com.apple.focus.work").
    ///
    /// This identifier comes from the system and is used to match Focus Mode
    /// activations. May not be available for all Focus Modes.
    var focusIdentifier: String

    /// User-visible name of the Focus Mode (e.g., "Work").
    ///
    /// Displayed in the UI and used for fuzzy matching when identifiers
    /// aren't available.
    var focusDisplayName: String

    // MARK: - Space Switching

    /// Space to switch all windows to when this Focus Mode activates.
    ///
    /// When `nil`, no space switching occurs.
    var targetSpaceID: UUID?

    // MARK: - Domain Restrictions

    /// Domains that show a blocking interstitial during this Focus Mode.
    ///
    /// Supports wildcards (e.g., "*.reddit.com") and exact matches.
    /// User can bypass with "Proceed Anyway" button.
    var restrictedDomains: [String]

    /// Domains that show blurred content until user explicitly reveals.
    ///
    /// Less restrictive than blocking - content is still accessible
    /// but requires an extra click to view.
    var blurredDomains: [String]

    // MARK: - Notifications

    /// Whether to suppress browser notifications during this Focus Mode.
    ///
    /// Complements system notification settings. Only affects Refrax
    /// notifications, not system-wide.
    var suppressNotifications: Bool

    // MARK: - State

    /// Whether this mapping is active.
    ///
    /// Disabled mappings are preserved but don't trigger actions.
    var isEnabled: Bool

    /// When this mapping was created.
    var createdAt: Date

    /// Last time this mapping triggered an action.
    var lastTriggeredAt: Date?

    // MARK: - Initialization

    init(focusIdentifier: String, focusDisplayName: String) {
        self.id = UUID()
        self.focusIdentifier = focusIdentifier
        self.focusDisplayName = focusDisplayName
        self.targetSpaceID = nil
        self.restrictedDomains = []
        self.blurredDomains = []
        self.suppressNotifications = false
        self.isEnabled = true
        self.createdAt = Date()
        self.lastTriggeredAt = nil
    }
}

// MARK: - Convenience

extension FocusModeMapping {
    /// Whether this mapping has any active restrictions.
    var hasRestrictions: Bool {
        !restrictedDomains.isEmpty || !blurredDomains.isEmpty
    }

    /// Whether this mapping will cause any action when triggered.
    var hasActions: Bool {
        targetSpaceID != nil || hasRestrictions || suppressNotifications
    }
}
