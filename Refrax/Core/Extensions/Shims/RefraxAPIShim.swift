import Foundation
import WebKit

/// Refrax's own extension API, `refrax.*`, served as the in-process native messaging host
/// ``hostName``.
///
/// `refrax-api-shim.js` defines `browser.refrax` in extension pages and sends each call through
/// `runtime.sendNativeMessage(hostName, {method, params})`, so the extension needs the
/// `nativeMessaging` permission, and per area the `refrax.tabs` or `refrax.spaces` permission
/// in its manifest. Replies are `{success: true, data}` or `{success: false, error}`.
///
/// | Method | Permission | Data |
/// |--------|------------|------|
/// | `tabs.getFavorites` | `refrax.tabs` | `[{id, title, url}]` |
/// | `tabs.setFavorite` `{tabId, isFavorite}` | `refrax.tabs` | `{isFavorite}` |
/// | `spaces.getAll` | `refrax.spaces` | `[{id, name, isPrivate}]` |
/// | `spaces.getCurrent` | `refrax.spaces` | `{id, name, isPrivate}` or `null` |
final class RefraxAPIShim {
    /// The host name extensions address Refrax's API by.
    static let hostName = "website.refrax.api"

    private enum Permission {
        static let tabs = "refrax.tabs"
        static let spaces = "refrax.spaces"
    }

    private unowned let state: BrowserState

    init(state: BrowserState) {
        self.state = state
    }

    /// Answers one call.
    func handle(_ message: Any, from context: WKWebExtensionContext) async throws -> Any? {
        guard let request = message as? [String: Any], let method = request["method"] as? String else {
            return Self.failure("Missing method")
        }
        let params = request["params"] as? [String: Any] ?? [:]
        let declared = Set(context.webExtension.manifest["permissions"] as? [String] ?? [])

        switch method {
        case "tabs.getFavorites":
            guard declared.contains(Permission.tabs) else { return Self.denied(Permission.tabs) }
            return Self.success(state.favoriteTabs.map(Self.describe))
        case "tabs.setFavorite":
            guard declared.contains(Permission.tabs) else { return Self.denied(Permission.tabs) }
            return setFavorite(params)
        case "spaces.getAll":
            guard declared.contains(Permission.spaces) else { return Self.denied(Permission.spaces) }
            return Self.success(state.spaces.map(Self.describe))
        case "spaces.getCurrent":
            guard declared.contains(Permission.spaces) else { return Self.denied(Permission.spaces) }
            let space = state.pagePool?.windowManager?.activeWindowController?.windowState.activeSpace
            return Self.success(space.map(Self.describe) ?? NSNull())
        default:
            return Self.failure("Unknown method: \(method)")
        }
    }

    private func setFavorite(_ params: [String: Any]) -> [String: Any] {
        guard let tabID = (params["tabId"] as? String).flatMap(UUID.init(uuidString:)),
              let isFavorite = params["isFavorite"] as? Bool
        else {
            return Self.failure("tabs.setFavorite needs {tabId, isFavorite}")
        }
        guard let tab = state.tab(for: tabID), let tabManager = state.pagePool?.tabManager else {
            return Self.failure("No tab with id \(tabID)")
        }
        if tab.isFavorite != isFavorite {
            tabManager.toggleFavorite(tab)
        }
        return Self.success(["isFavorite": tab.isFavorite])
    }

    private static func describe(_ tab: Tab) -> [String: Any] {
        ["id": tab.id.uuidString, "title": tab.displayTitle, "url": tab.activePage.url.absoluteString]
    }

    private static func describe(_ space: Space) -> [String: Any] {
        ["id": space.id.uuidString, "name": space.name, "isPrivate": space.dataStoreMode.isPrivate]
    }

    private static func success(_ data: Any) -> [String: Any] {
        ["success": true, "data": data]
    }

    private static func failure(_ message: String) -> [String: Any] {
        ["success": false, "error": message]
    }

    private static func denied(_ permission: String) -> [String: Any] {
        failure("Permission denied: \(permission)")
    }
}
