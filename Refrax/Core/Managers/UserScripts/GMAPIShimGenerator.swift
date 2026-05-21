import Foundation

/// Generates JavaScript shims for GM_* APIs.
///
/// The GM_* API provides Greasemonkey-compatible functions for user scripts:
/// - Storage: GM_getValue, GM_setValue, GM_deleteValue, GM_listValues
/// - Styling: GM_addStyle
/// - Clipboard: GM_setClipboard
/// - HTTP: GM_xmlhttpRequest
/// - Logging: GM_log
/// - Info: GM_info
///
/// APIs are only provided if explicitly requested via @grant.
///
/// ## Usage
///
/// ```swift
/// let shim = GMAPIShimGenerator.generate(
///     for: ["GM_getValue", "GM_setValue"],
///     namespace: "example.com"
/// )
/// ```
enum GMAPIShimGenerator {
    /// Generates JavaScript source for GM_* API shim.
    ///
    /// - Parameters:
    ///   - grants: Array of granted GM_* function names.
    ///   - namespace: Script namespace for storage isolation.
    /// - Returns: JavaScript source code, or empty string if no grants needed.
    static func generate(for grants: [String], namespace: String) -> String {
        // Check for @grant none
        if grants.contains("none") {
            return "// @grant none - no GM APIs"
        }

        var parts: [String] = []

        // Always provide GM_info (doesn't require grant)
        parts.append(generateInfoShim())

        // Generate requested APIs
        let grantSet = Set(grants.map { $0.lowercased() })

        // Storage APIs
        if grantSet.contains("gm_getvalue") || grantSet.contains("gm.getvalue") {
            parts.append(generateStorageGetShim(namespace: namespace))
        }
        if grantSet.contains("gm_setvalue") || grantSet.contains("gm.setvalue") {
            parts.append(generateStorageSetShim(namespace: namespace))
        }
        if grantSet.contains("gm_deletevalue") || grantSet.contains("gm.deletevalue") {
            parts.append(generateStorageDeleteShim(namespace: namespace))
        }
        if grantSet.contains("gm_listvalues") || grantSet.contains("gm.listvalues") {
            parts.append(generateStorageListShim(namespace: namespace))
        }

        // Style API
        if grantSet.contains("gm_addstyle") || grantSet.contains("gm.addstyle") {
            parts.append(generateAddStyleShim())
        }

        // Clipboard API
        if grantSet.contains("gm_setclipboard") || grantSet.contains("gm.setclipboard") {
            parts.append(generateClipboardShim(namespace: namespace))
        }

        // HTTP Request API
        if grantSet.contains("gm_xmlhttprequest") || grantSet.contains("gm.xmlhttprequest") {
            parts.append(generateXHRShim(namespace: namespace))
        }

        // Logging API
        if grantSet.contains("gm_log") || grantSet.contains("gm.log") {
            parts.append(generateLogShim())
        }

        // Generate the GM object wrapper
        parts.append(generateGMObjectWrapper(grants: grantSet, namespace: namespace))

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Info Shim

    private static func generateInfoShim() -> String {
        """
        // GM_info is always available
        if (typeof GM_info === 'undefined') {
            var GM_info = {
                scriptHandler: 'Refrax',
                version: '1.0',
                script: {}
            };
        }
        """
    }

    // MARK: - Storage Shims

    private static func generateStorageGetShim(namespace: String) -> String {
        let escapedNS = namespace.escapedForJS(quoteStyle: .single)
        return """
        async function GM_getValue(key, defaultValue) {
            try {
                const result = await webkit.messageHandlers.userscript.postMessage({
                    action: 'getValue',
                    namespace: '\(escapedNS)',
                    key: key,
                    defaultValue: defaultValue
                });
                return result !== undefined ? result : defaultValue;
            } catch (e) {
                console.error('[GM_getValue]', e);
                return defaultValue;
            }
        }
        """
    }

    private static func generateStorageSetShim(namespace: String) -> String {
        let escapedNS = namespace.escapedForJS(quoteStyle: .single)
        return """
        async function GM_setValue(key, value) {
            try {
                await webkit.messageHandlers.userscript.postMessage({
                    action: 'setValue',
                    namespace: '\(escapedNS)',
                    key: key,
                    value: value
                });
            } catch (e) {
                console.error('[GM_setValue]', e);
            }
        }
        """
    }

    private static func generateStorageDeleteShim(namespace: String) -> String {
        let escapedNS = namespace.escapedForJS(quoteStyle: .single)
        return """
        async function GM_deleteValue(key) {
            try {
                await webkit.messageHandlers.userscript.postMessage({
                    action: 'deleteValue',
                    namespace: '\(escapedNS)',
                    key: key
                });
            } catch (e) {
                console.error('[GM_deleteValue]', e);
            }
        }
        """
    }

    private static func generateStorageListShim(namespace: String) -> String {
        let escapedNS = namespace.escapedForJS(quoteStyle: .single)
        return """
        async function GM_listValues() {
            try {
                const result = await webkit.messageHandlers.userscript.postMessage({
                    action: 'listValues',
                    namespace: '\(escapedNS)'
                });
                return result || [];
            } catch (e) {
                console.error('[GM_listValues]', e);
                return [];
            }
        }
        """
    }

    // MARK: - Style Shim

    private static func generateAddStyleShim() -> String {
        """
        function GM_addStyle(css) {
            const style = document.createElement('style');
            style.textContent = css;
            (document.head || document.documentElement).appendChild(style);
            return style;
        }
        """
    }

    // MARK: - Clipboard Shim

    private static func generateClipboardShim(namespace: String) -> String {
        let escapedNS = namespace.escapedForJS(quoteStyle: .single)
        return """
        async function GM_setClipboard(text, type) {
            try {
                await webkit.messageHandlers.userscript.postMessage({
                    action: 'setClipboard',
                    namespace: '\(escapedNS)',
                    text: text,
                    type: type || 'text/plain'
                });
            } catch (e) {
                console.error('[GM_setClipboard]', e);
            }
        }
        """
    }

    // MARK: - XHR Shim

    private static func generateXHRShim(namespace: String) -> String {
        let escapedNS = namespace.escapedForJS(quoteStyle: .single)
        return """
        function GM_xmlhttpRequest(details) {
            return new Promise((resolve, reject) => {
                webkit.messageHandlers.userscript.postMessage({
                    action: 'xmlhttpRequest',
                    namespace: '\(escapedNS)',
                    details: {
                        method: details.method || 'GET',
                        url: details.url,
                        headers: details.headers || {},
                        data: details.data,
                        responseType: details.responseType || 'text',
                        timeout: details.timeout
                    }
                }).then(response => {
                    if (details.onload) {
                        details.onload(response);
                    }
                    resolve(response);
                }).catch(error => {
                    if (details.onerror) {
                        details.onerror({ error: error.message || String(error) });
                    }
                    reject(error);
                });
            });
        }
        """
    }

    // MARK: - Log Shim

    private static func generateLogShim() -> String {
        """
        function GM_log(...args) {
            console.log('[UserScript]', ...args);
        }
        """
    }

    // MARK: - GM Object Wrapper

    private static func generateGMObjectWrapper(grants: Set<String>, namespace _: String) -> String {
        var properties: [String] = []

        // Always include info
        properties.append("info: GM_info")

        if grants.contains("gm_getvalue") || grants.contains("gm.getvalue") {
            properties.append("getValue: GM_getValue")
        }
        if grants.contains("gm_setvalue") || grants.contains("gm.setvalue") {
            properties.append("setValue: GM_setValue")
        }
        if grants.contains("gm_deletevalue") || grants.contains("gm.deletevalue") {
            properties.append("deleteValue: GM_deleteValue")
        }
        if grants.contains("gm_listvalues") || grants.contains("gm.listvalues") {
            properties.append("listValues: GM_listValues")
        }
        if grants.contains("gm_addstyle") || grants.contains("gm.addstyle") {
            properties.append("addStyle: GM_addStyle")
        }
        if grants.contains("gm_setclipboard") || grants.contains("gm.setclipboard") {
            properties.append("setClipboard: GM_setClipboard")
        }
        if grants.contains("gm_xmlhttprequest") || grants.contains("gm.xmlhttprequest") {
            properties.append("xmlHttpRequest: GM_xmlhttpRequest")
        }
        if grants.contains("gm_log") || grants.contains("gm.log") {
            properties.append("log: GM_log")
        }

        let propsString = properties.joined(separator: ",\n    ")

        return """
        // GM object (modern API)
        const GM = {
            \(propsString)
        };
        """
    }
}
