import Foundation

/// Permission scopes that agents can request.
public enum PermissionScope: String, Codable, CaseIterable, Sendable {
    /// Read tab metadata (URL, title, ID, etc.)
    case tabsRead = "tabs:read"

    /// Modify tabs (create, close, navigate)
    case tabsWrite = "tabs:write"

    /// Read browsing history
    case historyRead = "history:read"

    /// Read page content (HTML, text)
    ///
    /// - Note: Also requires per-domain approval via `domainContentAccess`.
    case contentRead = "content:read"

    /// Modify browser settings
    case settingsWrite = "settings:write"

    /// Read and manage bookmarks
    case bookmarksRead = "bookmarks:read"

    /// Modify bookmarks
    case bookmarksWrite = "bookmarks:write"

    /// Read space metadata
    case spacesRead = "spaces:read"

    /// Create/modify/delete spaces
    case spacesWrite = "spaces:write"
}

/// Permission state for an agent session.
///
/// Tracks granted scopes and per-domain content access approvals.
/// Content access requires both the `contentRead` scope AND per-domain approval.
public struct AgentPermissions: Sendable {
    /// Currently granted permission scopes.
    public private(set) var grantedScopes: Set<PermissionScope>

    /// Per-domain content access approval timestamps.
    ///
    /// Key: Domain (e.g., "example.com")
    /// Value: When the approval was granted (session-scoped)
    ///
    /// These approvals expire when the session ends.
    public private(set) var domainContentAccess: [String: Date]

    /// Session identifier for tracking.
    public let sessionID: UUID

    /// When this permission state was created.
    public let createdAt: Date

    /// Creates a new permission state with no granted scopes.
    public init(sessionID: UUID = UUID()) {
        self.grantedScopes = []
        self.domainContentAccess = [:]
        self.sessionID = sessionID
        self.createdAt = Date()
    }

    /// Creates a permission state with initial scopes.
    public init(sessionID: UUID = UUID(), scopes: Set<PermissionScope>) {
        self.grantedScopes = scopes
        self.domainContentAccess = [:]
        self.sessionID = sessionID
        self.createdAt = Date()
    }

    // MARK: - Scope Checks

    /// Checks if a scope is granted.
    public func hasScope(_ scope: PermissionScope) -> Bool {
        grantedScopes.contains(scope)
    }

    /// Checks if all required scopes are granted.
    public func hasAllScopes(_ scopes: Set<PermissionScope>) -> Bool {
        scopes.isSubset(of: grantedScopes)
    }

    /// Checks if any of the scopes are granted.
    public func hasAnyScope(_ scopes: Set<PermissionScope>) -> Bool {
        !grantedScopes.isDisjoint(with: scopes)
    }

    // MARK: - Domain Content Access

    /// Checks if content access is approved for a domain.
    ///
    /// - Parameter domain: The domain to check (e.g., "example.com").
    /// - Returns: `true` if approved and `contentRead` scope is granted.
    public func hasContentAccess(for domain: String) -> Bool {
        guard hasScope(.contentRead) else { return false }
        return domainContentAccess[domain] != nil
    }

    /// Checks if content access is approved for a URL.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL's host is approved and `contentRead` scope is granted.
    public func hasContentAccess(for url: URL) -> Bool {
        guard let host = url.host else { return false }
        return hasContentAccess(for: host)
    }

    // MARK: - Mutations

    /// Grants a permission scope.
    public mutating func grant(_ scope: PermissionScope) {
        grantedScopes.insert(scope)
    }

    /// Grants multiple permission scopes.
    public mutating func grant(_ scopes: Set<PermissionScope>) {
        grantedScopes.formUnion(scopes)
    }

    /// Revokes a permission scope.
    public mutating func revoke(_ scope: PermissionScope) {
        grantedScopes.remove(scope)
    }

    /// Approves content access for a domain.
    ///
    /// - Parameter domain: The domain to approve (e.g., "example.com").
    public mutating func approveContentAccess(for domain: String) {
        domainContentAccess[domain] = Date()
    }

    /// Revokes content access for a domain.
    ///
    /// - Parameter domain: The domain to revoke access for.
    public mutating func revokeContentAccess(for domain: String) {
        domainContentAccess.removeValue(forKey: domain)
    }

    /// Clears all domain content access approvals.
    public mutating func clearContentAccess() {
        domainContentAccess.removeAll()
    }
}

// MARK: - Permission Requirements

/// Defines permission requirements for API operations.
public struct PermissionRequirements: Sendable {
    /// Required scopes (all must be granted).
    public let requiredScopes: Set<PermissionScope>

    /// Whether domain-specific content approval is needed.
    public let requiresDomainApproval: Bool

    public init(
        scopes: Set<PermissionScope> = [],
        requiresDomainApproval: Bool = false,
    ) {
        self.requiredScopes = scopes
        self.requiresDomainApproval = requiresDomainApproval
    }

    /// Checks if permissions satisfy these requirements.
    ///
    /// - Parameters:
    ///   - permissions: The agent's current permissions.
    ///   - domain: Optional domain for content access check.
    /// - Returns: `true` if all requirements are met.
    public func isSatisfied(by permissions: AgentPermissions, domain: String? = nil) -> Bool {
        guard permissions.hasAllScopes(requiredScopes) else {
            return false
        }

        if requiresDomainApproval, let domain {
            return permissions.hasContentAccess(for: domain)
        }

        return true
    }
}

// MARK: - Common Requirements

public extension PermissionRequirements {
    /// Requirements for reading tab information.
    static let tabsRead = PermissionRequirements(scopes: [.tabsRead])

    /// Requirements for modifying tabs.
    static let tabsWrite = PermissionRequirements(scopes: [.tabsWrite])

    /// Requirements for reading history.
    static let historyRead = PermissionRequirements(scopes: [.historyRead])

    /// Requirements for reading page content.
    static let contentRead = PermissionRequirements(
        scopes: [.contentRead],
        requiresDomainApproval: true,
    )

    /// Requirements for reading spaces.
    static let spacesRead = PermissionRequirements(scopes: [.spacesRead])

    /// Requirements for modifying spaces.
    static let spacesWrite = PermissionRequirements(scopes: [.spacesWrite])

    /// Requirements for reading bookmarks.
    static let bookmarksRead = PermissionRequirements(scopes: [.bookmarksRead])

    /// Requirements for modifying bookmarks.
    static let bookmarksWrite = PermissionRequirements(scopes: [.bookmarksWrite])
}
