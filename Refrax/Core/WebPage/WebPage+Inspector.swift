import Foundation
import WebKit

// MARK: - Web Inspector

extension WebPage {
    /// Shows the Web Inspector for this page.
    func showWebInspector() {
        webInspectorManager?.showInspector(for: tabPage.id, webView: backingWebView)
    }

    /// Closes the Web Inspector for this page.
    func closeWebInspector() {
        webInspectorManager?.closeInspector(for: tabPage.id, webView: backingWebView)
    }

    /// Toggles the Web Inspector visibility.
    func toggleWebInspector() {
        webInspectorManager?.toggleInspector(for: tabPage.id, webView: backingWebView)
    }

    /// Shows the JavaScript console in the Web Inspector.
    func showJavaScriptConsole() {
        webInspectorManager?.showJavaScriptConsole(for: tabPage.id, webView: backingWebView)
    }

    /// Shows the page resources in the Web Inspector.
    func showPageResources() {
        webInspectorManager?.showPageResources(for: tabPage.id, webView: backingWebView)
    }

    /// Shows the page source in the Web Inspector.
    func showPageSource() {
        webInspectorManager?.showPageSource(for: tabPage.id, webView: backingWebView)
    }

    /// Whether the Web Inspector is currently shown.
    var isInspectorShown: Bool {
        webInspectorManager?.isInspectorShown(for: tabPage.id) ?? false
    }

    /// Toggles page profiling (Timeline Recording) in the Web Inspector.
    func toggleTimelineRecording() {
        webInspectorManager?.togglePageProfiling(for: tabPage.id, webView: backingWebView)
    }

    /// Toggles element selection mode in the Web Inspector.
    func toggleElementSelection() {
        webInspectorManager?.toggleElementSelection(for: tabPage.id, webView: backingWebView)
    }

    /// Whether page profiling (Timeline Recording) is active.
    var isProfilingPage: Bool {
        webInspectorManager?.isProfilingPage(for: tabPage.id, webView: backingWebView) ?? false
    }

    /// Whether element selection mode is active.
    var isElementSelectionActive: Bool {
        webInspectorManager?.isElementSelectionActive(for: tabPage.id, webView: backingWebView) ?? false
    }

    /// Empties website caches for the current page's origin.
    func emptyCaches() {
        guard let url, let host = url.host(percentEncoded: false) else {
            Logger.warning("Cannot empty caches: no URL loaded", category: Logger.webview)
            return
        }

        Task {
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes: Set<String> = [
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeOfflineWebApplicationCache,
            ]

            let records = await dataStore.dataRecords(ofTypes: dataTypes)

            let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let matchingRecords = records.filter { record in
                let displayName = record.displayName
                let normalizedDisplayName = displayName.hasPrefix("www.") ? String(displayName.dropFirst(4)) : displayName
                return normalizedDisplayName == normalizedHost
            }

            if !matchingRecords.isEmpty {
                await dataStore.removeData(ofTypes: dataTypes, for: matchingRecords)
                Logger.info("Emptied caches for \(host)", category: Logger.webview)
            }
        }
    }
}
