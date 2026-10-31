import Foundation
import WebKit

/// Injects JavaScript shims into extension contexts for API compatibility.
///
/// The shim layer provides compatibility for WebExtension APIs that are not
/// natively supported by WebKit's `WKWebExtension`. Shims bridge JavaScript
/// calls to native Swift implementations via `webkit.messageHandlers`.
///
/// ## Architecture
///
/// ```
/// Extension JavaScript Code
///     │
///     ▼
/// Shim JavaScript (browser.storage.sync, etc.)
///     │
///     ▼ webkit.messageHandlers.refraxShim.postMessage()
///     │
/// ShimMessageHandler (Swift)
///     │
///     ▼
/// Native Implementation (StorageSyncShim, AlarmsShim, etc.)
/// ```
///
/// ## Injected APIs
///
/// | API | Native Support | Shim Implementation |
/// |-----|----------------|---------------------|
/// | `storage.local` | ✅ Native | - |
/// | `storage.sync` | ❌ | `NSUbiquitousKeyValueStore` |
/// | `contextMenus` | ❌ | `NSMenu` integration |
/// | `notifications` | ❌ | `UNUserNotificationCenter` |
/// | `alarms` | ❌ | `Timer` / `DispatchSourceTimer` |
/// | `downloads` | ❌ | `DownloadManager` bridge |
/// | `webRequest` | ❌ | Noop (network blocking via native WebKit) |
///
/// ## Usage
///
/// ```swift
/// let injector = ShimInjector()
/// injector.install(on: controllerConfiguration)   // before creating the controller
/// injector.extensionManager = extensionManager
/// ```
final class ShimInjector {
    // MARK: - Message Handler Names

    /// The message handler the shims call, `webkit.messageHandlers.refraxShim`.
    static let messageHandlerName = "refraxShim"

    // MARK: - Dependencies

    /// Resolves which extension sent a message, from the sending frame's origin.
    weak var extensionManager: ExtensionManager?

    /// The native shim implementations.
    private(set) lazy var storageSyncShim = StorageSyncShim()
    private(set) lazy var alarmsShim = AlarmsShim()
    private(set) lazy var notificationsShim = NotificationsShim()
    private(set) lazy var contextMenusShim = ContextMenusShim()
    private(set) lazy var downloadsShim = DownloadsShim()
    private(set) lazy var idleShim = IdleShim()

    // MARK: - Cached Scripts

    /// The combined shim JavaScript, loaded once from bundle.
    private lazy var shimScript: String = Self.loadShimScript()

    // MARK: - Installation

    /// Installs the shim scripts, their message handler, and Safari's user agent name on a
    /// controller configuration.
    ///
    /// Call before creating the controller. WebKit builds every extension page's
    /// configuration by copying the controller's, and the copies share its user content
    /// controller, so the shims run at document start in every page the controller's
    /// extensions open, background pages included.
    ///
    /// - Parameter configuration: The configuration the controller will be created with.
    func install(on configuration: WKWebExtensionController.Configuration) {
        let webViewConfiguration = configuration.webViewConfiguration ?? WKWebViewConfiguration()
        // Extension pages present themselves as Safari, as Refrax's web pages do. WebKit's
        // bare user agent names no browser, and extensions that pick their code paths by it
        // stop: Bitwarden's background page fails on a `null` device type.
        webViewConfiguration.applicationNameForUserAgent = UserAgentProvider.applicationName
        let userContentController = webViewConfiguration.userContentController
        userContentController.addUserScript(WKUserScript(
            source: shimScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page,
        ))
        userContentController.addScriptMessageHandler(
            ShimMessageHandler(injector: self),
            contentWorld: .page,
            name: Self.messageHandlerName,
        )
        configuration.webViewConfiguration = webViewConfiguration
    }

    // MARK: - Script Loading

    /// Loads the combined shim JavaScript from the bundle, in injection order.
    static func loadShimScript() -> String {
        var scripts: [String] = []

        // Load the base shim (namespace normalization, utilities)
        if let baseScript = loadScript(named: "shims") {
            scripts.append(baseScript)
        }

        // Load individual API shims
        let shimFiles = [
            "storage-sync-shim",
            "alarms-shim",
            "notifications-shim",
            "context-menus-shim",
            "downloads-shim",
            "web-request-shim",
            "refrax-api-shim",
        ]

        for file in shimFiles {
            if let script = loadScript(named: file) {
                scripts.append(script)
            }
        }

        let combined = scripts.joined(separator: "\n\n")

        if combined.isEmpty {
            Logger.warning(
                "No shim scripts found in bundle - extension compatibility may be limited",
                category: Logger.extensions,
            )
        }

        return combined
    }

    /// Loads a JavaScript file from the bundle.
    private static func loadScript(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else {
            Logger.debug("Shim script not found: \(name).js", category: Logger.extensions)
            return nil
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            Logger.error("Failed to load shim script \(name).js: \(error)", category: Logger.extensions)
            return nil
        }
    }
}

// MARK: - Message Handler

/// Handles JavaScript-to-Swift messages from extension shims.
///
/// Messages use a structured format:
/// ```json
/// {
///   "api": "storage.sync",
///   "method": "get",
///   "args": { "keys": ["setting1", "setting2"] },
///   "callbackId": "uuid-string"
/// }
/// ```
///
/// Responses are sent back via `replyHandler`:
/// ```json
/// {
///   "success": true,
///   "result": { "setting1": "value1" }
/// }
/// ```
/// or:
/// ```json
/// {
///   "success": false,
///   "error": "Error message"
/// }
/// ```
private final class ShimMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var injector: ShimInjector?

    init(injector: ShimInjector) {
        self.injector = injector
    }

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
    ) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let api = body["api"] as? String,
              let method = body["method"] as? String
        else {
            return (nil, "Invalid message format")
        }

        let args = body["args"] as? [String: Any] ?? [:]

        let origin = message.frameInfo.securityOrigin
        guard let injector, let manager = injector.extensionManager,
              let baseURL = URL(string: "\(origin.protocol)://\(origin.host)/"),
              let context = manager.extensionContext(for: baseURL)
        else {
            return (nil, "Message from a page that belongs to no extension")
        }

        if api == "permissions" {
            return await handlePermissions(method: method, args: args, context: context, manager: manager)
        }
        // The page's own shim checks nothing a page could not reach around, so each API's
        // permission is checked here.
        guard let required = Self.requiredPermissions[api] else {
            return (nil, ShimError.unsupportedAPI(api).localizedDescription)
        }
        guard required.contains(where: { manager.isGranted($0, to: context) }) else {
            return (nil, ShimError.permissionDenied.localizedDescription)
        }
        return await handleMessage(api: api, method: method, args: args, injector: injector, extensionIdentifier: context.uniqueIdentifier)
    }

    /// The permissions that let an extension use each shimmed API; any one of them is enough.
    private static let requiredPermissions: [String: [String]] = [
        "storage.sync": ["storage", "unlimitedStorage"],
        "alarms": ["alarms"],
        "notifications": ["notifications"],
        "contextMenus": ["contextMenus", "menus"],
        "downloads": ["downloads"],
        "idle": ["idle"],
    ]

    /// `permissions.contains`, `request`, `remove` and `getAll` for the permissions Refrax
    /// provides; `request` goes through the same prompt as WebKit's permissions.
    private func handlePermissions(
        method: String,
        args: [String: Any],
        context: WKWebExtensionContext,
        manager: ExtensionManager,
    ) async -> (Any?, String?) {
        let permissions = Set(args["permissions"] as? [String] ?? [])
        let result: Any
        switch method {
        case "contains":
            result = permissions.allSatisfy { manager.isGranted($0, to: context) }
        case "request":
            result = await manager.requestShimmedPermissions(permissions, for: context)
        case "remove":
            manager.removeShimmedPermissions(permissions, for: context)
            result = true
        case "getAll":
            result = manager.grantedShimmedPermissions(for: context)
        default:
            return (nil, ShimError.unsupportedMethod("permissions.\(method)").localizedDescription)
        }
        return (["success": true, "result": result], nil)
    }

    private func handleMessage(
        api: String,
        method: String,
        args: [String: Any],
        injector: ShimInjector,
        extensionIdentifier: String,
    ) async -> (Any?, String?) {
        do {
            let result: Any?

            switch api {
            case "storage.sync":
                result = try await injector.storageSyncShim.handle(
                    method: method,
                    args: args,
                    extensionID: extensionIdentifier,
                )

            case "alarms":
                result = try await injector.alarmsShim.handle(
                    method: method,
                    args: args,
                    extensionID: extensionIdentifier,
                )

            case "notifications":
                result = try await injector.notificationsShim.handle(
                    method: method,
                    args: args,
                    extensionID: extensionIdentifier,
                )

            case "contextMenus":
                result = try await injector.contextMenusShim.handle(
                    method: method,
                    args: args,
                    extensionID: extensionIdentifier,
                )

            case "downloads":
                result = try await injector.downloadsShim.handle(
                    method: method,
                    args: args,
                    extensionID: extensionIdentifier,
                )

            case "idle":
                result = try await injector.idleShim.handle(
                    method: method,
                    args: args,
                    extensionID: extensionIdentifier,
                )

            default:
                throw ShimError.unsupportedAPI(api)
            }

            return (["success": true, "result": result as Any], nil)

        } catch {
            Logger.warning(
                "Shim error for \(api).\(method): \(error.localizedDescription)",
                category: Logger.extensions,
            )
            return (nil, error.localizedDescription)
        }
    }
}

// MARK: - Shim Error

/// Errors that can occur in shim operations.
enum ShimError: Error, LocalizedError {
    case unsupportedAPI(String)
    case unsupportedMethod(String)
    case invalidArguments(String)
    case quotaExceeded
    case permissionDenied
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedAPI(api):
            "Unsupported API: \(api)"
        case let .unsupportedMethod(method):
            "Unsupported method: \(method)"
        case let .invalidArguments(details):
            "Invalid arguments: \(details)"
        case .quotaExceeded:
            "Storage quota exceeded"
        case .permissionDenied:
            "Permission denied"
        case let .notFound(item):
            "Not found: \(item)"
        }
    }
}

// MARK: - Shim Protocol

/// Protocol for native shim implementations.
protocol ExtensionShim {
    /// Handles a method call from JavaScript.
    ///
    /// - Parameters:
    ///   - method: The method name (e.g., "get", "set", "create").
    ///   - args: The arguments passed from JavaScript.
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: The result to send back to JavaScript.
    func handle(method: String, args: [String: Any], extensionID: String) async throws -> Any?
}
