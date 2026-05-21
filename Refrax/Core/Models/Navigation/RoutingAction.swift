import Foundation

/// An action to perform when a routing rule matches.
///
/// Actions determine where a URL should be opened when all conditions
/// of a routing rule are satisfied.
///
/// ## Examples
///
/// ```swift
/// // Open in a specific space
/// .openInSpace(workSpaceID)
///
/// // Open in a specific group within a space
/// .openInGroup(workSpaceID, groupID: meetingsGroupID)
///
/// // Create a new space from a template
/// .createSpace(SpaceTemplate(namePattern: "{domain}", color: .blue))
///
/// // Block the navigation
/// .block
/// ```
enum RoutingAction: Hashable, Sendable {
    /// Opens the URL in the specified space.
    ///
    /// If the space no longer exists, falls back to default behavior.
    case openInSpace(UUID)

    /// Opens the URL in a specific group within a space.
    ///
    /// If the group no longer exists, opens in the space without a group.
    case openInGroup(spaceID: UUID, groupID: UUID)

    /// Creates a new space using the template and opens the URL there.
    case createSpace(SpaceTemplate)

    /// Creates a new group in the specified space and opens the URL there.
    case createGroup(spaceID: UUID, template: GroupTemplate)

    /// Opens the URL in a Glimpse window instead of a tab.
    case openInGlimpse

    /// Opens the URL in a new background tab (not activated).
    ///
    /// Use this to load pages without interrupting the current view.
    case openInBackground

    /// Blocks the navigation entirely.
    ///
    /// Use this to prevent certain URLs from opening.
    case block

    // MARK: - Nested Types

    /// Template for creating a new space when a rule matches.
    struct SpaceTemplate: Codable, Hashable, Sendable {
        /// Pattern for the space name.
        ///
        /// Supports placeholders:
        /// - `{domain}` - URL host
        /// - `{subdomain}` - First part of host
        /// - `{path}` - First path component
        var namePattern: String

        /// Color for the new space (as hex string).
        var colorHex: String?

        /// SF Symbol name for the space icon.
        var iconName: String?

        /// Whether to use a separate data store for privacy.
        var useSeparateDataStore: Bool = false

        init(
            namePattern: String,
            colorHex: String? = nil,
            iconName: String? = nil,
            useSeparateDataStore: Bool = false,
        ) {
            self.namePattern = namePattern
            self.colorHex = colorHex
            self.iconName = iconName
            self.useSeparateDataStore = useSeparateDataStore
        }

        /// Expands the name pattern using values from the URL.
        func expandedName(for url: URL) -> String {
            expandNamePattern(namePattern, for: url)
        }
    }

    /// Template for creating a new tab group when a rule matches.
    struct GroupTemplate: Codable, Hashable, Sendable {
        /// Pattern for the group name.
        ///
        /// Supports the same placeholders as SpaceTemplate.
        var namePattern: String

        /// Color for the new group (as hex string).
        var colorHex: String?

        init(namePattern: String, colorHex: String? = nil) {
            self.namePattern = namePattern
            self.colorHex = colorHex
        }

        /// Expands the name pattern using values from the URL.
        func expandedName(for url: URL) -> String {
            expandNamePattern(namePattern, for: url)
        }
    }
}

// MARK: - Pattern Expansion

/// Expands a name pattern using placeholder values from the URL.
///
/// Supports placeholders:
/// - `{domain}` / `{host}` - URL host
/// - `{subdomain}` - First part of host (or full host if no subdomain)
/// - `{path}` - First path component (or "page" if empty)
private func expandNamePattern(_ pattern: String, for url: URL) -> String {
    var result = pattern

    if let host = url.host {
        result = result.replacingOccurrences(of: "{domain}", with: host)
        result = result.replacingOccurrences(of: "{host}", with: host)

        let parts = host.split(separator: ".")
        let subdomain = parts.count > 2 ? String(parts[0]) : host
        result = result.replacingOccurrences(of: "{subdomain}", with: subdomain)
    }

    let pathComponents = url.pathComponents.filter { $0 != "/" }
    let firstPath = pathComponents.first ?? "page"
    result = result.replacingOccurrences(of: "{path}", with: firstPath)

    return result
}

// MARK: - Codable

extension RoutingAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case spaceID
        case groupID
        case spaceTemplate
        case groupTemplate
    }

    private enum ActionType: String, Codable {
        case openInSpace
        case openInGroup
        case createSpace
        case createGroup
        case openInGlimpse
        case openInBackground
        case block
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .openInSpace:
            let spaceID = try container.decode(UUID.self, forKey: .spaceID)
            self = .openInSpace(spaceID)
        case .openInGroup:
            let spaceID = try container.decode(UUID.self, forKey: .spaceID)
            let groupID = try container.decode(UUID.self, forKey: .groupID)
            self = .openInGroup(spaceID: spaceID, groupID: groupID)
        case .createSpace:
            let template = try container.decode(SpaceTemplate.self, forKey: .spaceTemplate)
            self = .createSpace(template)
        case .createGroup:
            let spaceID = try container.decode(UUID.self, forKey: .spaceID)
            let template = try container.decode(GroupTemplate.self, forKey: .groupTemplate)
            self = .createGroup(spaceID: spaceID, template: template)
        case .openInGlimpse:
            self = .openInGlimpse
        case .openInBackground:
            self = .openInBackground
        case .block:
            self = .block
        }
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .openInSpace(spaceID):
            try container.encode(ActionType.openInSpace, forKey: .type)
            try container.encode(spaceID, forKey: .spaceID)
        case let .openInGroup(spaceID, groupID):
            try container.encode(ActionType.openInGroup, forKey: .type)
            try container.encode(spaceID, forKey: .spaceID)
            try container.encode(groupID, forKey: .groupID)
        case let .createSpace(template):
            try container.encode(ActionType.createSpace, forKey: .type)
            try container.encode(template, forKey: .spaceTemplate)
        case let .createGroup(spaceID, template):
            try container.encode(ActionType.createGroup, forKey: .type)
            try container.encode(spaceID, forKey: .spaceID)
            try container.encode(template, forKey: .groupTemplate)
        case .openInGlimpse:
            try container.encode(ActionType.openInGlimpse, forKey: .type)
        case .openInBackground:
            try container.encode(ActionType.openInBackground, forKey: .type)
        case .block:
            try container.encode(ActionType.block, forKey: .type)
        }
    }
}

// MARK: - Display

extension RoutingAction {
    /// A human-readable description of this action.
    var displayDescription: String {
        switch self {
        case let .openInSpace(spaceID):
            "Open in space \(spaceID.uuidString.prefix(8))..."
        case let .openInGroup(spaceID, groupID):
            "Open in group \(groupID.uuidString.prefix(8))... (space \(spaceID.uuidString.prefix(8))...)"
        case let .createSpace(template):
            "Create space \"\(template.namePattern)\""
        case let .createGroup(spaceID, template):
            "Create group \"\(template.namePattern)\" in space \(spaceID.uuidString.prefix(8))..."
        case .openInGlimpse:
            "Open in Glimpse window"
        case .openInBackground:
            "Open in background tab"
        case .block:
            "Block navigation"
        }
    }

    /// Short label for the action type.
    var typeLabel: String {
        switch self {
        case .openInSpace:
            "Space"
        case .openInGroup:
            "Group"
        case .createSpace:
            "New Space"
        case .createGroup:
            "New Group"
        case .openInGlimpse:
            "Glimpse"
        case .openInBackground:
            "Background"
        case .block:
            "Block"
        }
    }
}
