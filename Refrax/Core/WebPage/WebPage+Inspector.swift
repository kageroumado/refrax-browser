import Foundation
import WebKit

// MARK: - Web Inspector

extension WebPage {
    /// Shows the Web Inspector for this page.
    func showWebInspector() {
        if let enginePage {
            enginePage.perform(.devTools(command: .show))
            isEngineDevToolsShown = true
            return
        }
        webInspectorManager?.showInspector(for: tabPage.id, webView: backingWebView)
    }

    /// Closes the Web Inspector for this page.
    func closeWebInspector() {
        if let enginePage {
            enginePage.perform(.devTools(command: .hide))
            isEngineDevToolsShown = false
            return
        }
        webInspectorManager?.closeInspector(for: tabPage.id, webView: backingWebView)
    }

    /// Toggles the Web Inspector visibility.
    func toggleWebInspector() {
        if enginePage != nil {
            isEngineDevToolsShown ? closeWebInspector() : showWebInspector()
            return
        }
        webInspectorManager?.toggleInspector(for: tabPage.id, webView: backingWebView)
    }

    /// Shows the JavaScript console in the Web Inspector.
    func showJavaScriptConsole() {
        if let enginePage {
            enginePage.perform(.devTools(command: .showConsole))
            isEngineDevToolsShown = true
            return
        }
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

    /// Restores this page's inspector when it comes on screen.
    func inspectorPageDidBecomeVisible() {
        guard enginePage == nil else { return }
        webInspectorManager?.tabDidBecomeVisible(tabPage.id, webView: backingWebView)
    }

    /// Detaches this page's inspector before it leaves the screen.
    func inspectorPageWillBecomeHidden() {
        guard enginePage == nil else { return }
        webInspectorManager?.tabWillBecomeHidden(tabPage.id, webView: backingWebView)
    }

    /// Shows the inspector docked (`attached`) or in its own window. Engines choose their own placement.
    func showWebInspector(attached: Bool?) {
        guard enginePage == nil else { return showWebInspector() }
        webInspectorManager?.showInspector(for: tabPage.id, webView: backingWebView, attached: attached)
    }

    /// Toggles the inspector, opening it docked (`attached`) or in its own window.
    func toggleWebInspector(attached: Bool) {
        guard enginePage == nil else { return toggleWebInspector() }
        webInspectorManager?.toggleInspector(for: tabPage.id, webView: backingWebView, attached: attached)
    }

    /// Docks the WebKit inspector on `side`.
    func attachWebInspector(side: WebInspectorManager.AttachmentSide) {
        guard enginePage == nil else { return }
        webInspectorManager?.attachInspector(for: tabPage.id, webView: backingWebView, side: side)
    }

    /// Moves the WebKit inspector into its own window.
    func detachWebInspector() {
        guard enginePage == nil else { return }
        webInspectorManager?.detachInspector(for: tabPage.id, webView: backingWebView)
    }

    /// Shows the resources panel, a WebKit inspector feature.
    func showInspectorResources() {
        guard enginePage == nil else { return }
        webInspectorManager?.showPageResources(for: tabPage.id, webView: backingWebView)
    }

    /// Whether the Web Inspector is currently shown.
    var isInspectorShown: Bool {
        if enginePage != nil { return isEngineDevToolsShown }
        return webInspectorManager?.isInspectorShown(for: tabPage.id) ?? false
    }

    /// Toggles page profiling (Timeline Recording) in the Web Inspector.
    func toggleTimelineRecording() {
        webInspectorManager?.togglePageProfiling(for: tabPage.id, webView: backingWebView)
    }

    /// Toggles element selection mode in the Web Inspector.
    func toggleElementSelection() {
        if let enginePage {
            enginePage.perform(.devTools(command: .toggleElementSelection))
            return
        }
        webInspectorManager?.toggleElementSelection(for: tabPage.id, webView: backingWebView)
    }

    /// Whether page profiling (Timeline Recording) is active.
    var isProfilingPage: Bool {
        guard enginePage == nil else { return false }
        return webInspectorManager?.isProfilingPage(for: tabPage.id, webView: backingWebView) ?? false
    }

    /// Whether element selection mode is active.
    var isElementSelectionActive: Bool {
        guard enginePage == nil else { return false }
        return webInspectorManager?.isElementSelectionActive(for: tabPage.id, webView: backingWebView) ?? false
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
