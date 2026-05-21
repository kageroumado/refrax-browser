import AppKit
import Foundation
import WebKit

// Coordinates per-domain settings and applies them to WebPage instances.
//
// Design rationale:
// - Keep per-site decisions out of navigation handlers and view layers.
// - Apply settings at a single point (navigation commit) to avoid
//   redundant updates during provisional loads.
// - Make policy resolution (JavaScript, popups) reusable across
//   navigation and UI components.

final class SiteSettingsCoordinator {
    private let siteSettingsManager: SiteSettingsManager
    private let browserSettings: BrowserSettings

    init(siteSettingsManager: SiteSettingsManager, browserSettings: BrowserSettings) {
        self.siteSettingsManager = siteSettingsManager
        self.browserSettings = browserSettings
    }

    /// Applies per-domain settings to a WebPage after a navigation commits.
    func apply(to webPage: WebPage, for url: URL) {
        let siteSettings = siteSettingsManager.settings(for: url)
        let pageZoom = siteSettings?.pageZoom ?? 100
        if webPage.currentZoom != pageZoom {
            webPage.setZoom(pageZoom)
        }

        let contentBlockersEnabled = siteSettings?.enableContentBlockers ?? true
        if contentBlockersEnabled {
            webPage.clearContentBlockerBypass(for: url)
        } else {
            webPage.reloadWithoutContentBlockersIfNeeded(for: url)
        }

        // Note: Reader Mode (useReaderWhenAvailable) is handled by the UI layer.
        // The AddressBar observes page loading state and checks ReaderModeManager
        // for availability, automatically entering reader mode when the setting is enabled.

        // Note: Autoplay policy is enforced natively by WebKit via _autoplayPolicy
        // set on WKWebpagePreferences during navigation decisions. No need to apply here.

        // Apply per-site content appearance overrides
        applyContentProtectionOverride(to: webPage, siteSettings: siteSettings)
        applyDarkModeOverride(to: webPage, siteSettings: siteSettings)
        applyPageFilterOverride(to: webPage, siteSettings: siteSettings)
        applyBackgroundRemovalOverride(to: webPage, siteSettings: siteSettings)
    }

    // MARK: - Per-Site Content Appearance

    private func applyContentProtectionOverride(to webPage: WebPage, siteSettings: SiteSettings?) {
        let shouldBypass: Bool = if let override = siteSettings?.contentProtectionBypass {
            override
        } else {
            browserSettings.contentProtectionBypassEnabled
        }

        guard shouldBypass else { return }
        Task { _ = try? await webPage.evaluateJavaScript(ContentProtectionBypassScript.script) }
    }

    private func applyDarkModeOverride(to webPage: WebPage, siteSettings: SiteSettings?) {
        let override = siteSettings?.darkModeOverride ?? .auto
        let shouldApply: Bool = switch override {
        case .always:
            true
        case .never:
            false
        case .auto:
            switch browserSettings.webpageDarkMode {
            case .off: false
            case .always: true
            case .followSystem:
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua]) == .darkAqua
            }
        }

        guard shouldApply else { return }
        let script = DarkModeScript.detectionScript(preserveMedia: browserSettings.preserveMediaInFilter)
        Task { _ = try? await webPage.evaluateJavaScript(script) }
    }

    private func applyPageFilterOverride(to webPage: WebPage, siteSettings: SiteSettings?) {
        let override = siteSettings?.pageFilterOverride ?? .auto
        let filter: PageFilter = override.effectiveFilter ?? browserSettings.pageFilter

        guard filter != .none else { return }
        let script = PageFilterCSS.injectionScript(
            for: filter,
            preserveMedia: browserSettings.preserveMediaInFilter,
        )
        if !script.isEmpty {
            Task { _ = try? await webPage.evaluateJavaScript(script) }
        }

        // Apply color blindness SVG filters if needed
        if filter.requiresSVGFilters {
            Task { _ = try? await webPage.evaluateJavaScript(ColorBlindnessFilters.injectionScript) }
        }
    }

    private func applyBackgroundRemovalOverride(to webPage: WebPage, siteSettings: SiteSettings?) {
        let override = siteSettings?.backgroundRemovalOverride ?? .auto
        let mode: BackgroundRemovalMode = override.effectiveMode ?? browserSettings.backgroundRemovalMode

        guard mode != .none else { return }
        let script = BackgroundRemovalCSS.injectionScript(for: mode)
        if !script.isEmpty {
            Task { _ = try? await webPage.evaluateJavaScript(script) }
        }
    }

    /// Resolves JavaScript allowance for a URL with per-domain overrides.
    func allowsJavaScript(for url: URL) -> Bool {
        if let siteSettings = siteSettingsManager.settings(for: url) {
            if siteSettings.allowJavaScript == false {
                return false
            }

            if browserSettings.enableJavaScript {
                return true
            }

            return browserSettings.allowJavaScriptWhitelist && siteSettings.allowJavaScript
        }

        return browserSettings.enableJavaScript
    }

    /// Resolves the popup policy for a URL.
    func popUpPolicy(for url: URL) -> PopUpPolicy {
        if let siteSettings = siteSettingsManager.settings(for: url) {
            return siteSettings.popUpPolicy
        }

        return browserSettings.allowPopups ? .allow : .blockAndNotify
    }

    /// Resolves the autoplay policy for a URL.
    func autoPlayPolicy(for url: URL) -> AutoPlayPolicy {
        siteSettingsManager.settings(for: url)?.autoPlayPolicy ?? .stopMediaWithSound
    }

    /// Resolves the website coloring policy for a URL.
    ///
    /// Returns the per-site policy if set, otherwise `.useDefault`.
    func websiteColoringPolicy(for url: URL) -> WebsiteColoringPolicy {
        siteSettingsManager.settings(for: url)?.websiteColoringPolicy ?? .useDefault
    }

    /// Whether website coloring should be applied for a URL.
    ///
    /// Resolves the per-site policy against the global setting.
    /// - Returns: `true` if website coloring should be applied.
    func shouldApplyWebsiteColoring(for url: URL) -> Bool {
        let policy = websiteColoringPolicy(for: url)
        switch policy {
        case .allow:
            return true
        case .deny:
            return false
        case .useDefault:
            return browserSettings.enableWebsiteWindowColoring
        }
    }

    /// Whether website coloring should override space coloring for a URL.
    ///
    /// Only returns `true` if the site has an explicit `.allow` policy.
    func websiteColoringOverridesSpace(for url: URL) -> Bool {
        websiteColoringPolicy(for: url) == .allow
    }

    // MARK: - Badge Detection

    /// Checks for notification badges in a page title and marks the tab as unread if the count increased.
    ///
    /// Only marks as unread when:
    /// - Global badge detection is enabled
    /// - Per-site badge detection is not disabled
    /// - The page is not currently visible (background tab)
    /// - A notification pattern (e.g., "(3)") is detected in the title
    /// - The badge count is higher than the previously recorded count
    ///
    /// - Parameters:
    ///   - title: The page title to check for badge patterns.
    ///   - tab: The tab to potentially mark as unread.
    ///   - url: The URL for looking up per-site settings.
    ///   - isPageVisible: Whether the page is currently visible to the user.
    func checkBadgeAndMarkUnread(title: String, tab: Tab, url: URL, isPageVisible: Bool) {
        // Check global setting first (cheapest check)
        guard browserSettings.badgeDetectionEnabled else { return }

        // Check per-site setting
        let siteSettings = siteSettingsManager.settings(for: url)
        if siteSettings?.badgeDetection == .disabled { return }

        // Detect badge pattern and get count
        let newCount = BadgeDetector.detectBadge(in: title)

        // If page is visible, just update the count baseline without marking unread
        if isPageVisible {
            tab.lastBadgeCount = newCount
            return
        }

        // No badge detected
        guard let newCount else {
            // If the badge disappeared and the unread status was set by badge detection,
            // clear it (e.g., user read messages on another device)
            if tab.unreadFromBadge {
                tab.isUnread = false
                tab.unreadFromBadge = false
            }
            tab.lastBadgeCount = nil
            return
        }

        // Only mark unread if the count increased
        let previousCount = tab.lastBadgeCount ?? 0
        if newCount > previousCount {
            tab.isUnread = true
            tab.unreadFromBadge = true
        }

        // Always update the baseline
        tab.lastBadgeCount = newCount
    }
}
