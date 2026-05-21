import Foundation

/// Errors that can occur during Refrax API operations.
///
/// These errors are returned by ``RefraxAPI`` operations when they cannot complete successfully.
/// All errors include enough context for agents to understand what went wrong and how to proceed.
public enum RefraxError: Error, Sendable, CustomStringConvertible {
    // MARK: - Permission Errors

    /// Operation requires permission that hasn't been granted.
    case permissionDenied(scope: PermissionScope)

    /// Operation requires multiple permissions that haven't been granted.
    case permissionsDenied(scopes: Set<PermissionScope>)

    /// Content access requires per-domain approval.
    case domainApprovalRequired(domain: String)

    // MARK: - Not Found Errors

    /// Referenced tab does not exist.
    case tabNotFound(id: UUID)

    /// Referenced space does not exist.
    case spaceNotFound(id: UUID)

    /// Referenced tab group does not exist.
    case groupNotFound(id: UUID)

    /// Referenced history entry does not exist.
    case historyEntryNotFound(id: UUID)

    /// Referenced bookmark does not exist.
    case bookmarkNotFound(id: UUID)

    // MARK: - Invalid State Errors

    /// Operation cannot be performed in the current state.
    case invalidState(reason: String)

    /// No active window available for the operation.
    case noActiveWindow

    /// No active tab available for the operation.
    case noActiveTab

    /// The space has no tabs.
    case emptySpace(id: UUID)

    /// The space is locked and requires authentication.
    case spaceLocked(id: UUID, name: String)

    // MARK: - Validation Errors

    /// Invalid URL provided.
    case invalidURL(string: String)

    /// Invalid parameter value.
    case invalidParameter(name: String, reason: String)

    /// Operation would exceed a limit.
    case limitExceeded(limit: String, current: Int, max: Int)

    // MARK: - Execution Errors

    /// Navigation failed.
    case navigationFailed(url: String, reason: String)

    /// Content extraction failed.
    case contentExtractionFailed(reason: String)

    /// Internal error occurred.
    case internalError(reason: String)

    /// Operation timed out.
    case timeout(operation: String)

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case let .permissionDenied(scope):
            return "Permission denied: \(scope.rawValue) scope required"
        case let .permissionsDenied(scopes):
            let scopeNames = scopes.map(\.rawValue).sorted().joined(separator: ", ")
            return "Permissions denied: [\(scopeNames)] required"
        case let .domainApprovalRequired(domain):
            return "Content access requires user approval for domain: \(domain)"
        case let .tabNotFound(id):
            return "Tab not found: \(id)"
        case let .spaceNotFound(id):
            return "Space not found: \(id)"
        case let .groupNotFound(id):
            return "Tab group not found: \(id)"
        case let .historyEntryNotFound(id):
            return "History entry not found: \(id)"
        case let .bookmarkNotFound(id):
            return "Bookmark not found: \(id)"
        case let .invalidState(reason):
            return "Invalid state: \(reason)"
        case .noActiveWindow:
            return "No active window available"
        case .noActiveTab:
            return "No active tab available"
        case let .emptySpace(id):
            return "Space has no tabs: \(id)"
        case let .spaceLocked(id, name):
            return "Space '\(name)' is locked and requires authentication: \(id)"
        case let .invalidURL(string):
            return "Invalid URL: \(string)"
        case let .invalidParameter(name, reason):
            return "Invalid parameter '\(name)': \(reason)"
        case let .limitExceeded(limit, current, max):
            return "Limit exceeded for \(limit): \(current) > \(max)"
        case let .navigationFailed(url, reason):
            return "Navigation to \(url) failed: \(reason)"
        case let .contentExtractionFailed(reason):
            return "Content extraction failed: \(reason)"
        case let .internalError(reason):
            return "Internal error: \(reason)"
        case let .timeout(operation):
            return "Operation timed out: \(operation)"
        }
    }
}

// MARK: - LocalizedError

extension RefraxError: LocalizedError {
    public var errorDescription: String? {
        description
    }

    public var failureReason: String? {
        switch self {
        case .permissionDenied, .permissionsDenied:
            "The agent does not have the required permissions."
        case .domainApprovalRequired:
            "User approval is required to access content from this domain."
        case .tabNotFound, .spaceNotFound, .groupNotFound, .historyEntryNotFound, .bookmarkNotFound:
            "The requested resource could not be found."
        case .invalidState, .noActiveWindow, .noActiveTab, .emptySpace, .spaceLocked:
            "The operation cannot be performed in the current browser state."
        case .invalidURL, .invalidParameter, .limitExceeded:
            "The request contains invalid parameters."
        case .navigationFailed, .contentExtractionFailed, .internalError, .timeout:
            "The operation could not be completed."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case let .permissionDenied(scope):
            "Request the '\(scope.rawValue)' permission before performing this operation."
        case .domainApprovalRequired:
            "Request content access approval for the domain via the permission flow."
        case .noActiveWindow:
            "Wait for a browser window to become active."
        case .noActiveTab:
            "Ensure there is at least one tab open and active."
        case .emptySpace:
            "Create a tab in the space before performing this operation."
        case let .spaceLocked(_, name):
            "Space '\(name)' is locked. Unlock it via Touch ID before switching."
        case let .invalidURL(string):
            "Provide a valid URL instead of '\(string)'."
        case .timeout:
            "Try the operation again."
        default:
            nil
        }
    }
}
