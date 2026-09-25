import Foundation
import WebKit

// MARK: - Web Notifications

extension WebPage {
    /// The manager that asks, stores, and delivers this page's notifications.
    var webNotifications: WebNotificationManager? {
        backingNavigationDelegate.pagePool?.state.webNotifications
    }

    /// Whether the page belongs to a private space, whose pages never get notifications.
    var isInPrivateSpace: Bool {
        tabPage.tab?.space?.dataStoreMode == .private || !websiteDataStore.isPersistent
    }

    /// Answers `Notification.requestPermission()` from the stored decision or the user.
    func requestNotificationPermission(for origin: WebOrigin) async -> Bool {
        guard let webNotifications else { return false }
        return await webNotifications.requestPermission(for: origin, isPrivate: isInPrivateSpace, prompts: prompts)
    }

    /// Answers an engine's `notifications` permission request. Engines that can't deliver
    /// notifications are denied, so the page never expects them.
    func requestEngineNotificationPermission(for originURL: URL) async -> Bool {
        guard let enginePage, enginePage.engine.capabilities.contains(.notifications),
              let origin = WebOrigin(url: originURL)
        else { return false }
        return await requestNotificationPermission(for: origin)
    }

    /// Brings this page's tab forward, for a service worker's `client.focus()`.
    func focusFromServiceWorker() -> Bool {
        guard let tab = tabPage.tab, let webNotifications else { return false }
        webNotifications.focus(tab)
        return true
    }
}
