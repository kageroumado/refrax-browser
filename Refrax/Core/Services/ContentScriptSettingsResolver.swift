import AppKit
import Foundation

/// Resolves effective content script settings for a URL.
///
/// Combines global `BrowserSettings` with per-site `SiteSettings` overrides.
/// Used to determine which content scripts should be applied to a page.
///
/// ## Usage
///
/// ```swift
/// let resolver = ContentScriptSettingsResolver(
///     browserSettings: settings,
///     siteSettingsManager: siteManager
/// )
///
/// if resolver.shouldBypassContentProtection(for: url) {
///     // Apply content protection bypass script
/// }
/// ```
struct ContentScriptSettingsResolver {
    let browserSettings: BrowserSettings
    let siteSettingsManager: SiteSettingsManager

    /// Returns whether content protection bypass should be enabled for the URL.
    ///
    /// Checks site-specific override first, then falls back to global setting.
    func shouldBypassContentProtection(for url: URL) -> Bool {
        siteSettings(for: url)?.contentProtectionBypass
            ?? browserSettings.contentProtectionBypassEnabled
    }

    /// Returns whether dark mode should be applied for the URL.
    ///
    /// Resolution order:
    /// 1. Site-specific override (always/never)
    /// 2. Global preference (off/always/followSystem)
    /// 3. System appearance (for followSystem)
    func shouldApplyDarkMode(for url: URL) -> Bool {
        let siteOverride = siteSettings(for: url)?.darkModeOverride ?? .auto

        return switch siteOverride {
        case .always:
            true
        case .never:
            false
        case .auto:
            switch browserSettings.webpageDarkMode {
            case .off: false
            case .always: true
            case .followSystem: systemIsDarkMode
            }
        }
    }

    /// Returns the effective page filter for the URL.
    ///
    /// Site override takes precedence over global setting.
    func effectivePageFilter(for url: URL) -> PageFilter {
        siteSettings(for: url)?.pageFilterOverride.effectiveFilter
            ?? browserSettings.pageFilter
    }

    /// Returns the effective background removal mode for the URL.
    ///
    /// Site override takes precedence over global setting.
    func effectiveBackgroundRemoval(for url: URL) -> BackgroundRemovalMode {
        siteSettings(for: url)?.backgroundRemovalOverride.effectiveMode
            ?? browserSettings.backgroundRemovalMode
    }

    /// Returns whether media should be preserved when using invert/dark mode filters.
    var preserveMediaInFilter: Bool {
        browserSettings.preserveMediaInFilter
    }

    // MARK: - Private Helpers

    private func siteSettings(for url: URL) -> SiteSettings? {
        siteSettingsManager.settings(for: url)
    }

    private var systemIsDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua]) == .darkAqua
    }
}
