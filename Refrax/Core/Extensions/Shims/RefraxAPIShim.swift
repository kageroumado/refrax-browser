import Foundation
import WebKit

/// Provides Refrax-specific browser APIs to extensions.
///
/// `RefraxAPIShim` implements a `refrax.*` API namespace that extensions
/// can use to access Refrax-specific features like favorites, pinned tabs,
/// and spaces.
///
/// ## Available APIs
///
/// - `refrax.tabs.getFavorites()` - Get all favorited tabs
/// - `refrax.tabs.setFavorite(tabId, isFavorite)` - Set tab favorite status
/// - `refrax.tabs.getPinned()` - Get all pinned tabs
/// - `refrax.tabs.setPinned(tabId, isPinned)` - Set tab pinned status
/// - `refrax.spaces.getAll()` - Get all spaces
/// - `refrax.spaces.getCurrent()` - Get the current space
///
/// ## Permissions
///
/// Extensions must request the `refrax.tabs` permission to access favorites
/// and pinned status. The `refrax.spaces` permission is required for space APIs.
///
/// ## Implementation Status
///
/// This is a placeholder implementation. Full integration with BrowserState
/// will be added when the tab/space query APIs are implemented.
actor RefraxAPIShim {
    // MARK: - Types

    /// API response to JavaScript.
    struct APIResponse {
        let success: Bool
        let data: Any?
        let error: String?

        static func success(_ data: Any? = nil) -> APIResponse {
            APIResponse(success: true, data: data, error: nil)
        }

        static func error(_ message: String) -> APIResponse {
            APIResponse(success: false, data: nil, error: message)
        }
    }

    // MARK: - Properties

    /// Reference to browser state for tab/space access.
    private weak var state: BrowserState?

    /// Permission check function.
    private let hasPermission: @Sendable (String, WKWebExtensionContext) -> Bool

    // MARK: - Initialization

    /// Creates a Refrax API shim.
    ///
    /// - Parameters:
    ///   - state: The browser state for data access.
    ///   - hasPermission: Function to check if extension has a permission.
    init(
        state: BrowserState,
        hasPermission: @Sendable @escaping (String, WKWebExtensionContext) -> Bool,
    ) {
        self.state = state
        self.hasPermission = hasPermission
    }

    // MARK: - Message Handling

    /// Handles an API request from JavaScript.
    ///
    /// - Parameters:
    ///   - message: The API request message.
    ///   - context: The extension context making the request.
    /// - Returns: The API response to send back.
    func handleMessage(
        _ message: [String: Any],
        context: WKWebExtensionContext,
    ) async -> [String: Any] {
        guard let method = message["method"] as? String else {
            return encodeResponse(.error("Missing method"))
        }

        let params = message["params"] as? [String: Any] ?? [:]

        let response: APIResponse = switch method {
        // Tab APIs
        case "tabs.getFavorites":
            await getFavorites(context: context)

        case "tabs.setFavorite":
            await setFavorite(params: params, context: context)

        case "tabs.getPinned":
            await getPinned(context: context)

        case "tabs.setPinned":
            await setPinned(params: params, context: context)

        // Space APIs
        case "spaces.getAll":
            await getAllSpaces(context: context)

        case "spaces.getCurrent":
            await getCurrentSpace(context: context)

        default:
            .error("Unknown method: \(method)")
        }

        return encodeResponse(response)
    }

    // MARK: - Tab APIs (Stub Implementations)

    /// Gets all favorited tabs.
    ///
    /// - Note: Currently returns an error as this API is not yet implemented.
    private func getFavorites(context: WKWebExtensionContext) async -> APIResponse {
        guard hasPermission("refrax.tabs", context) else {
            return .error("Permission denied: refrax.tabs")
        }

        // TODO: Implement when BrowserState provides allTabs() API
        return .error("refrax.tabs.getFavorites is not yet implemented")
    }

    /// Sets the favorite status of a tab.
    ///
    /// - Note: Currently returns an error as this API is not yet implemented.
    private func setFavorite(
        params _: [String: Any],
        context: WKWebExtensionContext,
    ) async -> APIResponse {
        guard hasPermission("refrax.tabs", context) else {
            return .error("Permission denied: refrax.tabs")
        }

        // TODO: Implement when BrowserState provides tab lookup API
        return .error("refrax.tabs.setFavorite is not yet implemented")
    }

    /// Gets all pinned tabs.
    ///
    /// - Note: Currently returns an error as this API is not yet implemented.
    private func getPinned(context: WKWebExtensionContext) async -> APIResponse {
        guard hasPermission("refrax.tabs", context) else {
            return .error("Permission denied: refrax.tabs")
        }

        // TODO: Implement when BrowserState provides allTabs() API
        return .error("refrax.tabs.getPinned is not yet implemented")
    }

    /// Sets the pinned status of a tab.
    ///
    /// - Note: Currently returns an error as this API is not yet implemented.
    private func setPinned(
        params _: [String: Any],
        context: WKWebExtensionContext,
    ) async -> APIResponse {
        guard hasPermission("refrax.tabs", context) else {
            return .error("Permission denied: refrax.tabs")
        }

        // TODO: Implement when BrowserState provides tab lookup API
        return .error("refrax.tabs.setPinned is not yet implemented")
    }

    // MARK: - Space APIs (Stub Implementations)

    /// Gets all spaces.
    ///
    /// - Note: Currently returns an error as this API is not yet implemented.
    private func getAllSpaces(context: WKWebExtensionContext) async -> APIResponse {
        guard hasPermission("refrax.spaces", context) else {
            return .error("Permission denied: refrax.spaces")
        }

        // TODO: Implement when BrowserState provides allSpaces() API
        return .error("refrax.spaces.getAll is not yet implemented")
    }

    /// Gets the current space.
    ///
    /// - Note: Currently returns an error as this API is not yet implemented.
    private func getCurrentSpace(context: WKWebExtensionContext) async -> APIResponse {
        guard hasPermission("refrax.spaces", context) else {
            return .error("Permission denied: refrax.spaces")
        }

        // TODO: Implement when BrowserState provides current space API
        return .error("refrax.spaces.getCurrent is not yet implemented")
    }

    // MARK: - Private Helpers

    /// Encodes a response for JavaScript.
    private func encodeResponse(_ response: APIResponse) -> [String: Any] {
        var result: [String: Any] = ["success": response.success]
        if let data = response.data {
            result["data"] = data
        }
        if let error = response.error {
            result["error"] = error
        }
        return result
    }
}
