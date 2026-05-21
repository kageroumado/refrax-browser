import AppKit
import Foundation
import WebKit

/// Errors that can occur when handling user script messages.
enum UserScriptError: LocalizedError {
    case invalidMessage
    case unknownAction(String)
    case unauthorizedDomain(String)
    case internalNetworkBlocked
    case requestFailed(String)
    case scriptNotFound

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            "Invalid message format"
        case let .unknownAction(action):
            "Unknown action: \(action)"
        case let .unauthorizedDomain(domain):
            "Unauthorized domain for cross-origin request: \(domain)"
        case .internalNetworkBlocked:
            "Requests to internal/local networks are blocked"
        case let .requestFailed(reason):
            "Request failed: \(reason)"
        case .scriptNotFound:
            "Script not found for namespace"
        }
    }
}

/// Handles messages from user scripts for GM_* API implementation.
///
/// This handler receives messages posted via `webkit.messageHandlers.userscript.postMessage()`
/// from the injected GM_* API shim and executes the corresponding native operations.
///
/// ## Supported Actions
///
/// - `getValue` - Read from persistent storage
/// - `setValue` - Write to persistent storage
/// - `deleteValue` - Remove from persistent storage
/// - `listValues` - List storage keys
/// - `setClipboard` - Copy text to clipboard
/// - `xmlhttpRequest` - Make cross-origin HTTP request
///
/// ## Security
///
/// - Storage is isolated by script namespace
/// - Cross-origin requests require @connect whitelist
/// - Internal/local network requests are blocked even with wildcard @connect
final class UserScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    private weak var scriptManager: UserScriptManager?
    private let storageManager: UserScriptStorageManager

    // MARK: - Initialization

    init(scriptManager: UserScriptManager, storageManager: UserScriptStorageManager) {
        self.scriptManager = scriptManager
        self.storageManager = storageManager
        super.init()
    }

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
    ) async -> (Any?, String?) {
        do {
            let result = try await handleMessage(message)
            return (result, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: WKScriptMessage) async throws -> Any? {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let namespace = body["namespace"] as? String else {
            throw UserScriptError.invalidMessage
        }

        switch action {
        case "getValue":
            return try await handleGetValue(body: body, namespace: namespace)

        case "setValue":
            try await handleSetValue(body: body, namespace: namespace)
            return nil

        case "deleteValue":
            try await handleDeleteValue(body: body, namespace: namespace)
            return nil

        case "listValues":
            return try await handleListValues(namespace: namespace)

        case "setClipboard":
            handleSetClipboard(body: body)
            return nil

        case "xmlhttpRequest":
            return try await handleXHRRequest(body: body, namespace: namespace)

        default:
            throw UserScriptError.unknownAction(action)
        }
    }

    // MARK: - Storage Actions

    private func handleGetValue(body: [String: Any], namespace: String) async throws -> Any? {
        guard let key = body["key"] as? String else {
            throw UserScriptError.invalidMessage
        }

        let defaultValue = body["defaultValue"]

        // Get JSON data from storage
        guard let jsonData = try await storageManager.getValue(key: key, namespace: namespace) else {
            return defaultValue
        }

        // Decode JSON - we store wrapped in {"v": value} container
        guard let container = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return defaultValue
        }

        return container["v"] ?? defaultValue
    }

    private func handleSetValue(body: [String: Any], namespace: String) async throws {
        guard let key = body["key"] as? String,
              let value = body["value"] else {
            throw UserScriptError.invalidMessage
        }

        // Wrap value in container to handle all JSON types (including primitives)
        let container: [String: Any] = ["v": value]
        let jsonData = try JSONSerialization.data(withJSONObject: container)

        try await storageManager.setValue(key: key, jsonData: jsonData, namespace: namespace)
    }

    private func handleDeleteValue(body: [String: Any], namespace: String) async throws {
        guard let key = body["key"] as? String else {
            throw UserScriptError.invalidMessage
        }

        try await storageManager.deleteValue(key: key, namespace: namespace)
    }

    private func handleListValues(namespace: String) async throws -> [String] {
        try await storageManager.listValues(namespace: namespace)
    }

    // MARK: - Clipboard Action

    private func handleSetClipboard(body: [String: Any]) {
        guard let text = body["text"] as? String else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - XHR Action

    private func handleXHRRequest(body: [String: Any], namespace: String) async throws -> [String: Any] {
        guard let details = body["details"] as? [String: Any],
              let urlString = details["url"] as? String,
              let url = URL(string: urlString) else {
            throw UserScriptError.invalidMessage
        }

        // Verify domain is allowed
        try validateXHRDomain(url: url, namespace: namespace)

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = (details["method"] as? String) ?? "GET"

        // Add headers
        if let headers = details["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add body
        if let data = details["data"] as? String {
            request.httpBody = data.data(using: .utf8)
        }

        // Set timeout
        if let timeout = details["timeout"] as? Double {
            request.timeoutInterval = timeout / 1_000.0 // Convert ms to seconds
        }

        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Build response object
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserScriptError.requestFailed("Invalid response")
        }

        let responseType = (details["responseType"] as? String) ?? "text"
        let responseText: String?
        let responseJSON: Any?

        if responseType == "json" {
            responseText = nil
            responseJSON = try? JSONSerialization.jsonObject(with: data)
        } else {
            responseText = String(data: data, encoding: .utf8)
            responseJSON = nil
        }

        return [
            "status": httpResponse.statusCode,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
            "responseHeaders": httpResponse.allHeaderFields,
            "responseText": responseText as Any,
            "response": responseJSON ?? responseText as Any,
            "finalUrl": httpResponse.url?.absoluteString ?? urlString,
        ]
    }

    private func validateXHRDomain(url: URL, namespace: String) throws {
        guard let host = url.host?.lowercased() else {
            throw UserScriptError.invalidMessage
        }

        // Block internal/local network regardless of @connect
        if isInternalNetwork(host: host) {
            throw UserScriptError.internalNetworkBlocked
        }

        // Find the script by namespace to check @connect whitelist
        guard let script = scriptManager?.scripts.first(where: { $0.namespace == namespace }) else {
            throw UserScriptError.scriptNotFound
        }

        // Check if domain is allowed
        let allowedDomains = script.connectDomains

        // Wildcard allows all (except internal, checked above)
        if allowedDomains.contains("*") {
            return
        }

        // Check if host matches any allowed domain
        let isAllowed = allowedDomains.contains { domain in
            let pattern = domain.lowercased()

            // Exact match
            if host == pattern {
                return true
            }

            // Subdomain match (pattern is suffix)
            if host.hasSuffix(".\(pattern)") {
                return true
            }

            // Wildcard subdomain (*.domain.com)
            if pattern.hasPrefix("*.") {
                let baseDomain = String(pattern.dropFirst(2))
                return host == baseDomain || host.hasSuffix(".\(baseDomain)")
            }

            return false
        }

        if !isAllowed {
            throw UserScriptError.unauthorizedDomain(host)
        }
    }

    private func isInternalNetwork(host: String) -> Bool {
        // Localhost
        if host == "localhost" { return true }

        // IPv4 loopback
        if host == "127.0.0.1" { return true }
        if host.hasPrefix("127.") { return true }

        // IPv6 loopback
        if host == "::1" || host == "[::1]" { return true }

        // Private IPv4 ranges
        if host.hasPrefix("10.") { return true }
        if host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("172.") {
            // 172.16.0.0 - 172.31.255.255
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]) {
                if second >= 16, second <= 31 {
                    return true
                }
            }
        }

        // Link-local
        if host.hasPrefix("169.254.") { return true }

        return false
    }
}
