import Foundation
import WebKit

/// Refrax's own extension API, `refrax.*`, served as the in-process native messaging host
/// ``hostName``.
///
/// `refrax-api-shim.js` defines `browser.refrax` in extension pages and sends each call through
/// `runtime.sendNativeMessage(hostName, {method, params})`, so the extension needs the
/// `nativeMessaging` permission. Each area needs its permission, `refrax.tabs` or
/// `refrax.spaces`, granted to the installed extension (installing grants what the manifest
/// declares). Replies are `{success: true, data}` or `{success: false, error}`.
///
/// An extension sees and changes only what runs in its own controller: the default
/// controller's extensions see the global spaces and the favorites, a space with its own
/// data store's extensions see that space. Private spaces need the extension to be allowed in
/// private mode on top of that.
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

    /// The prefix of the permissions this API defines, which WebKit does not know.
    static let permissionPrefix = "refrax."

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
        guard let manager = state.extensionManager, let installed = manager.installedExtension(for: context) else {
            return Self.failure("Extension is not installed")
        }
        let caller = Caller(manager: manager, context: context, installed: installed)

        switch method {
        case "tabs.getFavorites":
            guard caller.isGranted(Permission.tabs) else { return Self.denied(Permission.tabs) }
            return Self.success(state.favoriteTabs.filter(caller.owns).map(Self.describe))
        case "tabs.setFavorite":
            guard caller.isGranted(Permission.tabs) else { return Self.denied(Permission.tabs) }
            return setFavorite(params, caller: caller)
        case "spaces.getAll":
            guard caller.isGranted(Permission.spaces) else { return Self.denied(Permission.spaces) }
            return Self.success(state.spaces.filter(caller.owns).map(Self.describe))
        case "spaces.getCurrent":
            guard caller.isGranted(Permission.spaces) else { return Self.denied(Permission.spaces) }
            let space = state.pagePool?.windowManager?.activeWindowController?.windowState.activeSpace
            return Self.success(space.flatMap { caller.owns($0) ? Self.describe($0) : nil } ?? NSNull())
        default:
            return Self.failure("Unknown method: \(method)")
        }
    }

    /// The calling extension: what it was granted and what runs in its controller.
    private struct Caller {
        let manager: ExtensionManager
        let context: WKWebExtensionContext
        let installed: InstalledExtension

        func isGranted(_ permission: String) -> Bool {
            installed.grantedPermissions[permission].map { $0 > Date() } ?? false
        }

        func owns(_ space: Space) -> Bool {
            guard !space.dataStoreMode.isPrivate || installed.allowedInPrivateMode else { return false }
            return manager.existingController(for: space) === context.webExtensionController
        }

        func owns(_ tab: Tab) -> Bool {
            if let space = tab.space, space.dataStoreMode.isPrivate, !installed.allowedInPrivateMode {
                return false
            }
            return manager.existingController(for: tab) === context.webExtensionController
        }
    }

    private func setFavorite(_ params: [String: Any], caller: Caller) -> [String: Any] {
        guard let tabID = (params["tabId"] as? String).flatMap(UUID.init(uuidString:)),
              let isFavorite = params["isFavorite"] as? Bool
        else {
            return Self.failure("tabs.setFavorite needs {tabId, isFavorite}")
        }
        guard let tab = state.tab(for: tabID), caller.owns(tab), let tabManager = state.pagePool?.tabManager else {
            return Self.failure("No tab with id \(tabID)")
        }
        // A favorite belongs to every space and the global data store, so only a tab that
        // already runs there may become one.
        if isFavorite, caller.manager.existingController(for: tab) !== caller.manager.defaultController {
            return Self.failure("Tabs of this space cannot become favorites")
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
