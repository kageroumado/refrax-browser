import AppIntents
import AppKit

/// Refrax Focus Filter for system Focus Mode integration.
///
/// This implements `SetFocusFilterIntent` to allow users to configure
/// Refrax behavior when different Focus Modes activate (Work, Personal,
/// Sleep/Bedtime, etc.).
///
/// ## Configuration
///
/// Users configure the filter in System Settings > Focus > [Focus Name] > Add Filter > Refrax.
/// Available settings:
/// - Target Space: Switch to a specific space when Focus activates
/// - Blocked Domains: Sites to block during this Focus
/// - Blurred Domains: Sites to blur until revealed
/// - Suppress Notifications: Hide browser notifications
///
/// ## Architecture
///
/// ```
/// System Focus Changes
///        │
///        ▼
/// RefraxFocusFilter.perform()
///        │
///        ├── Read configured parameters
///        └── Apply via FocusModeManager
///                │
///                ├── Switch space (if configured)
///                ├── Apply domain restrictions
///                └── Update notification settings
/// ```
struct RefraxFocusFilter: SetFocusFilterIntent {
    // MARK: - Metadata

    nonisolated static let title: LocalizedStringResource = "Refrax Browser"

    nonisolated static let description = IntentDescription(
        "Configure Refrax behavior for this Focus",
        categoryName: "Browser",
    )

    // MARK: - Parameters

    /// The space to switch to when this Focus activates.
    @Parameter(title: "Switch to Space")
    var targetSpaceName: String?

    /// Domains to block during this Focus.
    @Parameter(title: "Block Sites", description: "Sites that will show a blocked page (comma-separated)")
    var blockedDomains: String?

    /// Domains to blur during this Focus.
    @Parameter(title: "Blur Sites", description: "Sites that will be blurred until you reveal them (comma-separated)")
    var blurredDomains: String?

    /// Whether to suppress browser notifications.
    @Parameter(title: "Suppress Notifications", default: false)
    var suppressNotifications: Bool

    // MARK: - Display Representation

    var displayRepresentation: DisplayRepresentation {
        var subtitle = ""

        if let spaceName = targetSpaceName, !spaceName.isEmpty {
            subtitle = "Space: \(spaceName)"
        }

        if let blocked = blockedDomains, !blocked.isEmpty {
            let count = blocked.components(separatedBy: ",").count
            if !subtitle.isEmpty { subtitle += ", " }
            subtitle += "\(count) blocked"
        }

        if let blurred = blurredDomains, !blurred.isEmpty {
            let count = blurred.components(separatedBy: ",").count
            if !subtitle.isEmpty { subtitle += ", " }
            subtitle += "\(count) blurred"
        }

        if subtitle.isEmpty {
            subtitle = "No restrictions"
        }

        return DisplayRepresentation(
            title: "Refrax Browser",
            subtitle: "\(subtitle)",
        )
    }

    // MARK: - Execution

    @MainActor
    func perform() async throws -> some IntentResult {
        let appDelegate = NSApplication.shared.delegate as? AppDelegate
        guard let appDelegate else {
            throw FocusFilterError.appNotRunning
        }

        // Parse domain lists
        let blocked = parseDomainList(blockedDomains)
        let blurred = parseDomainList(blurredDomains)

        // Find target space if specified
        var targetSpaceID: UUID?
        if let spaceName = targetSpaceName, !spaceName.isEmpty {
            if let space = appDelegate.browserState.spaces.first(where: {
                $0.name.localizedCaseInsensitiveCompare(spaceName) == .orderedSame
            }) {
                targetSpaceID = space.id
            }
            // Note: We don't throw if space not found - just skip space switching
        }

        // Apply restrictions via RestrictionEnforcer
        RestrictionEnforcer.shared.updateFocusRestrictions(
            blockedDomains: blocked,
            blurredDomains: blurred,
            suppressNotifications: suppressNotifications,
            focusIdentifier: "system-focus-filter",
        )

        // Switch space if configured and space exists
        if let targetSpaceID,
           let space = appDelegate.browserState.space(for: targetSpaceID) {
            let windowStates = appDelegate.windowManager.allWindowStates

            for windowState in windowStates {
                // Check if space is locked
                if !appDelegate.browserState.spaceLockManager.requiresAuth(for: space) {
                    appDelegate.spaceManager.switchToSpaceSync(space, for: windowState)
                }
            }

            Logger.info("Focus Filter: Switched to space '\(space.name)'", category: Logger.ui)
        }

        Logger.info(
            "Focus Filter applied: \(blocked.count) blocked, \(blurred.count) blurred, notifications: \(!suppressNotifications)",
            category: Logger.ui,
        )

        return .result()
    }

    // MARK: - Helpers

    private func parseDomainList(_ list: String?) -> [String] {
        guard let list, !list.isEmpty else { return [] }

        return list
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Focus Filter Error

/// Errors that can occur during Focus Filter execution.
enum FocusFilterError: Error, CustomLocalizedStringResourceConvertible {
    case appNotRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotRunning:
            "Refrax is not running"
        }
    }
}

// MARK: - Space Entity

/// App Entity representing a Refrax Space for Focus Filter configuration.
///
/// This allows users to select a space from a picker in Focus settings.
struct SpaceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Space")

    nonisolated(unsafe) static var defaultQuery = SpaceEntityQuery()

    let id: UUID
    let name: String
    let iconName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: iconName),
        )
    }
}

/// Query for fetching Space entities.
struct SpaceEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SpaceEntity] {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return []
        }

        return identifiers.compactMap { id in
            guard let space = appDelegate.browserState.space(for: id) else { return nil }
            return SpaceEntity(id: space.id, name: space.name, iconName: space.iconName)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SpaceEntity] {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return []
        }

        return appDelegate.browserState.spaces.map { space in
            SpaceEntity(id: space.id, name: space.name, iconName: space.iconName)
        }
    }
}
