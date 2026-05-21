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
/// let injector = ShimInjector(extensionManager: extensionManager)
/// injector.configure(context: extensionContext)
/// ```
final class ShimInjector {
    // MARK: - Message Handler Names

    /// The base message handler name for shim communication.
    /// Actual handler names are suffixed with extension identifier.
    static let messageHandlerBaseName = "refraxShim"

    // MARK: - State

    /// Tracks which extension contexts have been configured to avoid duplicate handler registration.
    private var configuredContexts: Set<String> = []

    // MARK: - Dependencies

    unowned let extensionManager: ExtensionManager

    /// The native shim implementations.
    private(set) lazy var storageSyncShim = StorageSyncShim()
    private(set) lazy var alarmsShim = AlarmsShim()
    private(set) lazy var notificationsShim = NotificationsShim()
    private(set) lazy var contextMenusShim = ContextMenusShim()
    private(set) lazy var downloadsShim = DownloadsShim()

    // Refrax-specific API shim will be enabled when BrowserState APIs are available
    // private(set) lazy var refraxAPIShim: RefraxAPIShim = { ... }()

    // MARK: - Cached Scripts

    /// The combined shim JavaScript, loaded once from bundle.
    private lazy var shimScript: String = loadShimScript()

    // MARK: - Initialization

    /// Creates a shim injector.
    ///
    /// - Parameter extensionManager: The extension manager for context access.
    init(extensionManager: ExtensionManager) {
        self.extensionManager = extensionManager
    }

    // MARK: - Configuration

    /// Configures an extension context with shim scripts and message handlers.
    ///
    /// Call this after loading the context into the controller (when webViewConfiguration
    /// becomes available). This sets up:
    /// 1. JavaScript shims injected at document start
    /// 2. Native message handler for JavaScript-to-Swift calls
    ///
    /// Safe to call multiple times - duplicate configuration is skipped.
    ///
    /// - Parameter context: The extension context to configure.
    func configure(context: WKWebExtensionContext) {
        let extensionID = context.uniqueIdentifier

        // Skip if already configured (prevents duplicate handler crash on reload)
        guard !configuredContexts.contains(extensionID) else {
            Logger.debug(
                "Shims already configured for extension: \(extensionID), skipping",
                category: Logger.extensions,
            )
            return
        }

        guard let configuration = context.webViewConfiguration else {
            Logger.warning(
                "Extension context has no webViewConfiguration, skipping shim injection",
                category: Logger.extensions,
            )
            return
        }

        // Use extension-specific handler name to avoid conflicts between extensions
        let handlerName = "\(Self.messageHandlerBaseName)_\(extensionID)"

        // Create shim script with the correct handler name injected
        let scriptWithHandler = shimScript.replacingOccurrences(
            of: "webkit.messageHandlers.refraxShim",
            with: "webkit.messageHandlers.\(handlerName)",
        )

        // Add the shim user script
        let userScript = WKUserScript(
            source: scriptWithHandler,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page,
        )
        configuration.userContentController.addUserScript(userScript)

        // Add the message handler for native callbacks
        let messageHandler = ShimMessageHandler(
            injector: self,
            extensionIdentifier: extensionID,
        )
        configuration.userContentController.addScriptMessageHandler(
            messageHandler,
            contentWorld: .page,
            name: handlerName,
        )

        // Mark as configured
        configuredContexts.insert(extensionID)

        Logger.debug(
            "Configured shims for extension: \(extensionID)",
            category: Logger.extensions,
        )
    }

    /// Removes shim configuration for an extension context.
    ///
    /// Call this when unloading an extension to allow reconfiguration if reloaded.
    ///
    /// - Parameter context: The extension context to unconfigure.
    func unconfigure(context: WKWebExtensionContext) {
        let extensionID = context.uniqueIdentifier
        configuredContexts.remove(extensionID)

        // Note: We don't remove the script message handler here because
        // the webViewConfiguration may be shared or already deallocated.
        // WebKit handles cleanup when the context is destroyed.
    }

    // MARK: - Script Loading

    /// Loads the combined shim JavaScript from the bundle.
    private func loadShimScript() -> String {
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
    private func loadScript(named name: String) -> String? {
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
    let extensionIdentifier: String

    init(injector: ShimInjector, extensionIdentifier: String) {
        self.injector = injector
        self.extensionIdentifier = extensionIdentifier
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

        return await handleMessage(api: api, method: method, args: args)
    }

    private func handleMessage(
        api: String,
        method: String,
        args: [String: Any],
    ) async -> (Any?, String?) {
        guard let injector else {
            return (nil, "Shim injector deallocated")
        }

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

            case "refraxAPI":
                // Refrax-specific APIs are not yet implemented
                // TODO: Enable when BrowserState provides allTabs/allSpaces APIs
                throw ShimError.unsupportedAPI("refraxAPI (not yet implemented)")

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
