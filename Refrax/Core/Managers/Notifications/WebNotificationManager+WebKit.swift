import Foundation
import WebKit

// MARK: - Attaching to WebKit

extension WebNotificationManager {
    /// Makes the data store read notification permissions from Refrax and send service worker
    /// windows to Refrax's tabs. Call before the first web view using the store is created,
    /// since a web process reads its permissions when it launches.
    ///
    /// Ephemeral stores are left alone: WebKit denies their notifications itself.
    func adopt(_ dataStore: WKWebsiteDataStore) {
        guard dataStore.isPersistent, dataStore._delegate !== dataStoreDelegate else { return }
        dataStore._delegate = dataStoreDelegate
    }

    /// Installs Refrax's provider on the process pool of `webView`, once per pool, and on
    /// WebKit's shared service worker manager the first time.
    func attach(to webView: WKWebView) {
        installServiceWorkerProviderIfNeeded()
        let key = RFXWebNotificationProvider.managerKey(for: webView)
        guard providers[key] == nil else { return }
        let provider = RFXWebNotificationProvider(webView: webView)
        provider.delegate = providerDelegate
        provider.install()
        providers[key] = provider
    }

    private func installServiceWorkerProviderIfNeeded() {
        guard serviceWorkerProvider == nil else { return }
        let provider = RFXWebNotificationProvider.serviceWorkerProvider()
        provider.delegate = providerDelegate
        provider.install()
        serviceWorkerProvider = provider
    }

    /// The installed provider for a manager.
    func provider(forManagerKey key: UInt) -> RFXWebNotificationProvider? {
        if let serviceWorkerProvider, serviceWorkerProvider.managerKey == key {
            return serviceWorkerProvider
        }
        return providers[key]
    }

    /// Drops the provider of a destroyed process pool and its deliveries' routes.
    func providerDidDetach(_ provider: RFXWebNotificationProvider) {
        let key = providers.first { $0.value === provider }?.key
        if let key {
            providers.removeValue(forKey: key)
            forgetDeliveries { source in
                if case let .webKit(managerKey, _) = source { managerKey == key } else { false }
            }
        }
    }

    // MARK: Notifications from WebKit

    /// A notification WebKit asked a provider to show.
    func show(_ notification: RFXWebNotification, from provider: RFXWebNotificationProvider) {
        guard let origin = WebOrigin(string: notification.origin) else {
            Logger.warning("Dropped a notification from an unsupported origin: \(notification.origin)", category: Logger.notifications)
            return
        }
        let page = notification.page.flatMap(webPage(for:))
        let tab = page?.tabPage.tab
        let incoming = IncomingWebNotification(
            source: .webKit(managerKey: provider.managerKey, identifier: notification.identifier),
            origin: origin,
            title: notification.title,
            body: notification.body,
            tag: notification.tag.isEmpty ? nil : notification.tag,
            iconURL: notification.iconURL,
            isSilent: notification.isSilent,
            isPersistent: notification.isPersistent,
            tabPageID: page?.tabPage.id,
            tabID: tab?.id,
            spaceID: tab?.space?.id,
            dataStoreID: notification.dataStoreIdentifier,
            persistentRepresentation: notification.dictionaryRepresentation.flatMap(Self.encodePersistentRepresentation),
        )
        deliver(incoming) {
            provider.didShow(notification.identifier)
        }
    }

    /// The page closed a notification, or WebKit cleared a page's notifications.
    func withdraw(_ identifiers: [UInt64], from provider: RFXWebNotificationProvider) {
        let sources = identifiers.map { IncomingWebNotification.Source.webKit(managerKey: provider.managerKey, identifier: $0) }
        withdraw(sources)
    }

    /// WebKit forgot the notification; a click can no longer reach it through the provider.
    func forget(_ identifier: UInt64, from provider: RFXWebNotificationProvider) {
        let source = IncomingWebNotification.Source.webKit(managerKey: provider.managerKey, identifier: identifier)
        if let request = requestsBySource.removeValue(forKey: source) {
            sourcesByRequest.removeValue(forKey: request)
        }
    }

    /// The Refrax page showing a WebKit page.
    private func webPage(for pageRef: WKPageRef) -> WebPage? {
        pagePool?.activePages.values.first { $0.backingWebView._pageRefForTransitionToWKWebView == pageRef }
    }

    // MARK: Persistent Representation

    /// A service worker notification's WebKit description as a binary property list, or nil
    /// when it is larger than ``Constants/maximumPersistentRepresentationBytes``.
    static func encodePersistentRepresentation(_ dictionary: [AnyHashable: Any]) -> Data? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0),
              data.count <= Constants.maximumPersistentRepresentationBytes
        else { return nil }
        return data
    }

    /// The description ``encodePersistentRepresentation(_:)`` stored.
    static func decodePersistentRepresentation(_ data: Data) -> [AnyHashable: Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any]
    }
}

// MARK: - Provider Delegate

/// Forwards a notification provider's callbacks to the manager.
final class WebNotificationProviderDelegate: NSObject, RFXWebNotificationProviderDelegate {
    weak var manager: WebNotificationManager?

    func notificationProvider(_ provider: RFXWebNotificationProvider, show notification: RFXWebNotification) {
        manager?.show(notification, from: provider)
    }

    func notificationProvider(_ provider: RFXWebNotificationProvider, cancel identifier: UInt64) {
        manager?.withdraw([identifier], from: provider)
    }

    func notificationProvider(_ provider: RFXWebNotificationProvider, didDestroy identifier: UInt64) {
        manager?.forget(identifier, from: provider)
    }

    func notificationProvider(_ provider: RFXWebNotificationProvider, clear identifiers: [NSNumber]) {
        manager?.withdraw(identifiers.map(\.uint64Value), from: provider)
    }

    func notificationPermissions(for _: RFXWebNotificationProvider) -> [String: NSNumber] {
        manager?.permissionMap ?? [:]
    }

    func notificationProviderDidDetach(_ provider: RFXWebNotificationProvider) {
        manager?.providerDidDetach(provider)
    }
}

// MARK: - Data Store Delegate

/// The delegate of every persistent data store: notification permissions for its web
/// processes, and tabs for its service workers.
final class WebNotificationDataStoreDelegate: NSObject, _WKWebsiteDataStoreDelegate {
    weak var manager: WebNotificationManager?

    func notificationPermissions(forWebsiteDataStore _: WKWebsiteDataStore) -> [String: NSNumber] {
        manager?.permissionMap ?? [:]
    }

    func websiteDataStore(
        _ dataStore: WKWebsiteDataStore,
        openWindow url: URL,
        fromServiceWorkerOrigin _: WKSecurityOrigin,
        completionHandler: @escaping (WKWebView?) -> Void,
    ) {
        completionHandler(manager?.openServiceWorkerWindow(url, in: dataStore))
    }

    func websiteDataStore(_ dataStore: WKWebsiteDataStore, navigateToNotificationActionURL url: URL) {
        _ = manager?.openServiceWorkerWindow(url, in: dataStore)
    }
}
