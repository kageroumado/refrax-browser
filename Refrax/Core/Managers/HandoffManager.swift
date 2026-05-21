import AppKit
import Foundation

/// Manages Handoff functionality using NSUserActivity.
///
/// Handoff allows users to continue browsing seamlessly across Apple devices.
/// When a user is viewing a webpage on Mac, the activity appears on their iPhone/iPad,
/// and vice versa.
///
/// ## Architecture
///
/// ```
/// WebPage URL change → HandoffManager.updateActivity() → NSUserActivity
///                                                              ↓
///                                                         System Handoff
///                                                              ↓
/// AppDelegate.application(_:continue:) ← Incoming from other device
/// ```
///
/// ## Usage
///
/// ```swift
/// let handoff = HandoffManager()
///
/// // When tab becomes active or URL changes
/// handoff.updateActivity(for: tab)
///
/// // When tab becomes inactive
/// handoff.invalidateActivity()
/// ```
@Observable
final class HandoffManager {
    // MARK: - Properties

    /// The current user activity being advertised for Handoff.
    @ObservationIgnored
    private var currentActivity: NSUserActivity?

    /// Whether Handoff is currently enabled.
    private(set) var isEnabled = true

    // MARK: - Activity Management

    /// Updates the current Handoff activity for the given tab.
    ///
    /// Respects privacy by not advertising tabs in private or separate-data spaces.
    ///
    /// Call this when:
    /// - A tab becomes active
    /// - Navigation completes in the active tab
    /// - The page title updates
    ///
    /// - Parameter tab: The tab to advertise. Pass `nil` to clear the activity.
    func updateActivity(for tab: Tab?) {
        guard isEnabled else { return }

        guard let tab,
              shouldAdvertise(tab: tab) else {
            invalidateActivity()
            return
        }

        // Use activePage to get the currently focused page in multi-page tabs,
        // rather than pages.first which might not be the visible page
        let activePage = tab.activePage
        updateActivity(for: activePage.url, title: activePage.title)
    }

    /// Checks whether a tab should be advertised via Handoff.
    ///
    /// Tabs in private spaces are not advertised to protect privacy. Separate (isolated)
    /// spaces are fine to advertise as they're for organizational purposes like work contexts.
    ///
    /// - Parameter tab: The tab to check.
    /// - Returns: `true` if the tab should be advertised, `false` otherwise.
    func shouldAdvertise(tab: Tab) -> Bool {
        guard let space = tab.space else { return false }
        return space.dataStoreMode != .private
    }

    /// Updates the current Handoff activity for the given URL.
    ///
    /// - Note: Prefer using `updateActivity(for tab:)` which includes privacy checks.
    ///
    /// - Parameters:
    ///   - url: The URL of the current page. Must be http/https.
    ///   - title: The page title for display on the receiving device.
    func updateActivity(for url: URL?, title: String?) {
        guard isEnabled else { return }

        guard let url, url.scheme == "http" || url.scheme == "https" else {
            invalidateActivity()
            return
        }

        let activity = currentActivity ?? createActivity()
        activity.webpageURL = url
        activity.title = title ?? url.host ?? url.absoluteString
        activity.becomeCurrent()

        Logger.debug("Handoff activity updated: \(url.absoluteString)", category: Logger.tabs)
    }

    private func createActivity() -> NSUserActivity {
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        currentActivity = activity
        return activity
    }

    /// Invalidates the current Handoff activity.
    ///
    /// Call this when:
    /// - The active tab changes to a non-web page
    /// - The window becomes inactive
    /// - The app resigns active
    func invalidateActivity() {
        currentActivity?.invalidate()
        currentActivity = nil
    }

    /// Temporarily disables Handoff activity updates.
    ///
    /// Use this during bulk operations or when the user has disabled Handoff.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            invalidateActivity()
        }
    }

    // MARK: - Activity Type Constants

    /// Refrax-specific activity type for Handoff between Refrax instances.
    static let refraxActivityType = "com.refrax.browsing"

    // MARK: - Incoming Activity

    /// Handles an incoming Handoff activity from another device.
    ///
    /// - Parameter userActivity: The activity to continue.
    /// - Returns: The URL to open, if valid.
    static func extractURL(from userActivity: NSUserActivity) -> URL? {
        let validTypes = [NSUserActivityTypeBrowsingWeb, refraxActivityType]
        guard validTypes.contains(userActivity.activityType) else {
            return nil
        }

        return userActivity.webpageURL
    }
}
