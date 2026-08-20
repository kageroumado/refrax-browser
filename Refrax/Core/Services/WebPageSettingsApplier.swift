import Foundation
import WebKit

/// Applies global browser settings to WebPage configuration and requests.
///
/// Design rationale:
/// - Keep WebPage construction deterministic by centralizing configuration mutations.
/// - Avoid duplicating settings logic across TabManager/WebPagePool/WebPage.
/// - Provide a single place to evolve request headers (e.g., DNT, GPC) and
///   data store selection (including private mode isolation).
/// - Prefer SwiftData-backed site settings for header gating so Settings can
///   query and mutate policy without app updates.
struct WebPageSettingsApplier {
    let settings: BrowserSettings
    let deviceSensorAuthorization: WebPage.DeviceSensorAuthorization
    let siteSettingsManager: SiteSettingsManager

    /// Applies browser settings to a WebPage configuration.
    func apply(to configuration: inout WebPage.Configuration) {
        configuration.defaultNavigationPreferences.allowsContentJavaScript = settings.enableJavaScript
        configuration.deviceSensorAuthorization = deviceSensorAuthorization
        configuration.suppressesIncrementalRendering = false
        configuration.allowsInlinePredictions = true
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.elementFullscreenMode = settings.elementFullscreenMode

        // Feature flag overrides
        let overrides = settings.featureFlagOverrides
        configuration.featureFlagOverrides = overrides
        configuration.disableCORS = settings.isFeatureFlagEnabled("app.disableCORS", default: false)
    }

    /// Applies browser-controlled headers to a request.
    func applyRequestHeaders(to request: inout URLRequest) {
        if settings.doNotTrack, request.value(forHTTPHeaderField: "DNT") == nil {
            request.setValue("1", forHTTPHeaderField: "DNT")
        }
        applyGPCHeader(to: &request)
    }

    private func applyGPCHeader(to request: inout URLRequest) {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return
        }

        let shouldSend = settings.enableGlobalPrivacyControl && isGPCHeaderAllowed(for: url)

        if shouldSend {
            if request.value(forHTTPHeaderField: "Sec-GPC") == nil {
                request.setValue("1", forHTTPHeaderField: "Sec-GPC")
            }
        } else if request.value(forHTTPHeaderField: "Sec-GPC") != nil {
            request.setValue(nil, forHTTPHeaderField: "Sec-GPC")
        }
    }

    private func isGPCHeaderAllowed(for url: URL) -> Bool {
        siteSettingsManager.settings(for: url)?.gpcHeaderOverride == .allow
    }

    /// Resolves the appropriate data store for a tab based on its space's data store mode.
    func dataStore(
        for tab: Tab,
        spaceProvider: (Space.ID) -> Space?,
        spaceDataStoreManager: SpaceDataStoreManager,
    ) -> WKWebsiteDataStore {
        // Special tabs (like new tab page) always use global data store
        if tab.status.usesGlobalDataStore {
            return .default()
        }

        // Get the space's data store based on its mode
        guard let spaceID = tab.space?.id,
              let space = spaceProvider(spaceID)
        else {
            return .default()
        }

        return spaceDataStoreManager.dataStore(for: space)
    }

    /// Returns the default data store for contexts without a space.
    func defaultDataStore() -> WKWebsiteDataStore {
        .default()
    }
}
