import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UserNotifications
import WebKit

// MARK: - Delivering

extension WebNotificationManager {
    /// Shows a notification in Notification Center when its origin is allowed and macOS
    /// permits it, then calls `didShow`.
    func deliver(_ notification: IncomingWebNotification, didShow: @escaping () -> Void) {
        guard store.state(for: notification.origin) == .granted else {
            Logger.info("Dropped a notification from \(notification.origin): not allowed", category: Logger.notifications)
            return
        }
        let requestID = WebNotificationContentBuilder.requestIdentifier(for: notification, uniqueID: UUID())
        if let replaced = sourcesByRequest[requestID] {
            requestsBySource.removeValue(forKey: replaced)
        }
        sourcesByRequest[requestID] = notification.source
        requestsBySource[notification.source] = requestID

        Task(name: "Deliver web notification") {
            await requestSystemAuthorizationIfNeeded()
            guard systemAllowsNotifications else {
                Logger.info("macOS doesn't allow Refrax's notifications; dropped one from \(notification.origin)", category: Logger.notifications)
                return
            }
            let userInfo = WebNotificationUserInfo(notification: notification, notificationID: requestID)
            let content = WebNotificationContentBuilder.content(for: notification, userInfo: userInfo)
            if let attachment = await iconAttachment(for: notification) {
                content.attachments = [attachment]
            }
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: requestID, content: content, trigger: nil))
                store.recordNotification(from: notification.origin)
                didShow()
            } catch {
                Logger.error("Couldn't show a notification from \(notification.origin): \(error)", category: Logger.notifications)
            }
        }
    }

    /// Removes the notifications from Notification Center; the page closed them.
    func withdraw(_ sources: [IncomingWebNotification.Source]) {
        let requests = sources.compactMap { requestsBySource.removeValue(forKey: $0) }
        guard !requests.isEmpty else { return }
        for request in requests {
            sourcesByRequest.removeValue(forKey: request)
        }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: requests)
        center.removePendingNotificationRequests(withIdentifiers: requests)
    }

    /// Forgets the deliveries whose source matches, leaving them in Notification Center.
    func forgetDeliveries(where matches: (IncomingWebNotification.Source) -> Bool) {
        for (source, request) in requestsBySource where matches(source) {
            requestsBySource.removeValue(forKey: source)
            sourcesByRequest.removeValue(forKey: request)
        }
    }

    // MARK: Icons

    /// The page's icon, else the site's cached favicon, as an image file macOS can attach.
    private func iconAttachment(for notification: IncomingWebNotification) async -> UNNotificationAttachment? {
        var data: Data?
        if let iconURL = notification.iconURL, ["http", "https"].contains(iconURL.scheme?.lowercased()) {
            data = await Self.downloadIcon(from: iconURL)
        }
        if data == nil, let faviconCache = pagePool?.state.faviconCache {
            data = await faviconCache.cachedFaviconData(forHost: notification.origin.host, size: .large)
        }
        guard let data, let file = await Self.writeIconFile(data) else { return nil }
        return try? UNNotificationAttachment(
            identifier: "icon",
            url: file.url,
            options: [UNNotificationAttachmentOptionsTypeHintKey: file.typeIdentifier],
        )
    }

    private nonisolated static let iconSession = URLSession(configuration: .ephemeral)

    @concurrent
    private nonisolated static func downloadIcon(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.iconTimeout
        guard let (data, response) = try? await iconSession.data(for: request),
              (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true,
              data.count <= Constants.maximumIconBytes
        else { return nil }
        return data
    }

    /// Writes image data to a temporary file named for its type; nil when it isn't an image.
    @concurrent
    private nonisolated static func writeIconFile(_ data: Data) async -> (url: URL, typeIdentifier: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?
        else { return nil }
        let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "png"
        let directory = FileManager.default.temporaryDirectory.appending(path: "WebNotificationIcons", directoryHint: .isDirectory)
        let url = directory.appending(path: "\(UUID().uuidString).\(fileExtension)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return (url, typeIdentifier)
        } catch {
            return nil
        }
    }
}

// MARK: - Responding

extension WebNotificationManager {
    /// What the user did with a delivered web notification.
    enum Response: Sendable {
        case clicked
        case dismissed
    }

    /// Routes a click or dismissal back to the page or service worker, and brings the site forward on a click.
    func handle(_ response: Response, to userInfo: WebNotificationUserInfo) {
        let source = sourcesByRequest.removeValue(forKey: userInfo.notificationID)
        if let source {
            requestsBySource.removeValue(forKey: source)
        }
        switch response {
        case .clicked:
            NSApp.activate()
            if userInfo.isPersistent {
                clickPersistent(userInfo, source: source)
            } else {
                if let source {
                    sendClick(to: source)
                }
                showSite(for: userInfo, openingIfNeeded: true)
            }
        case .dismissed:
            if let source {
                sendClose(to: source)
            }
        }
    }

    private func sendClick(to source: IncomingWebNotification.Source) {
        switch source {
        case let .webKit(managerKey, identifier):
            provider(forManagerKey: managerKey)?.didClick(identifier)
        case let .engine(pageID, identifier):
            pagePool?.existingPage(for: pageID)?.enginePage?.perform(.notificationClicked(id: identifier))
        }
    }

    private func sendClose(to source: IncomingWebNotification.Source) {
        switch source {
        case let .webKit(managerKey, identifier):
            provider(forManagerKey: managerKey)?.didClose([NSNumber(value: identifier)])
        case let .engine(pageID, identifier):
            pagePool?.existingPage(for: pageID)?.enginePage?.perform(.notificationClosed(id: identifier))
        }
    }

    /// Fires the service worker's `notificationclick`. The worker decides what to show, through
    /// `clients.openWindow` or `client.focus()`; Refrax opens the site itself only when no worker
    /// handled the click.
    private func clickPersistent(_ userInfo: WebNotificationUserInfo, source: IncomingWebNotification.Source?) {
        if let data = userInfo.persistentRepresentation,
           let representation = Self.decodePersistentRepresentation(data),
           let dataStore = dataStore(withID: userInfo.dataStoreID) {
            // WebKit completes on the main thread, with the network process's reply.
            dataStore._processPersistentNotificationClick(representation) { [weak self] handled in
                MainActor.assumeIsolated {
                    if !handled {
                        self?.showSite(for: userInfo, openingIfNeeded: true)
                    }
                }
            }
        } else if let source {
            sendClick(to: source)
        } else {
            showSite(for: userInfo, openingIfNeeded: true)
        }
    }

    // MARK: Showing the Site

    /// Brings forward the tab that showed the notification, else a tab already on the origin
    /// in the right space, else opens the origin in a new tab there.
    func showSite(for userInfo: WebNotificationUserInfo, openingIfNeeded: Bool) {
        guard let state = pagePool?.state else { return }
        if let tabID = userInfo.tabID, let tab = state.tab(for: tabID), !tab.isArchived {
            focus(tab)
            return
        }
        let space = space(for: userInfo)
        if let tab = space?.tabs.first(where: { !$0.isArchived && WebOrigin(url: $0.activePage.url) == userInfo.origin }) {
            focus(tab)
            return
        }
        guard openingIfNeeded, let space, let url = userInfo.origin.url else { return }
        openTab(url, in: space)
    }

    /// Opens `url` for a service worker's `clients.openWindow` in a space using `dataStore`,
    /// and returns the web view loading it.
    func openServiceWorkerWindow(_ url: URL, in dataStore: WKWebsiteDataStore) -> WKWebView? {
        guard let space = space(using: dataStore), let tab = openTab(url, in: space) else { return nil }
        return pagePool?.existingPage(for: tab.activePage)?.backingWebView
    }

    @discardableResult
    private func openTab(_ url: URL, in space: Space) -> Tab? {
        guard let tabManager = pagePool?.tabManager else { return nil }
        let tab = tabManager.createTab(url: url, in: space, makeActive: false, loadImmediately: true)
        focus(tab)
        return tab
    }

    /// Selects `tab` in a window showing its space, switching the frontmost window to the
    /// space when none does, and brings the window forward.
    func focus(_ tab: Tab) {
        guard let pagePool, let tabManager = pagePool.tabManager, let windowManager = pagePool.windowManager else { return }
        NSApp.activate()
        guard let space = tab.space else {
            if let controller = windowManager.activeWindowController {
                tabManager.setActiveTab(tab, in: controller.windowState)
                controller.window?.makeKeyAndOrderFront(nil)
            }
            return
        }
        if let controller = windowManager.windowController(for: space) {
            tabManager.setActiveTab(tab, in: controller.windowState)
            controller.window?.makeKeyAndOrderFront(nil)
        } else if let controller = windowManager.activeWindowController {
            if !pagePool.state.spaceLockManager.requiresAuth(for: space) {
                tabManager.spaceManager.switchToSpaceSync(space, for: controller.windowState, restoreActiveTab: false)
                tabManager.setActiveTab(tab, in: controller.windowState)
            }
            controller.window?.makeKeyAndOrderFront(nil)
        } else {
            windowManager.createWindow(with: space, activating: tab)
        }
    }

    // MARK: Spaces and Data Stores

    /// The space a notification belongs to: the one that showed it, else one using its data store.
    private func space(for userInfo: WebNotificationUserInfo) -> Space? {
        guard let state = pagePool?.state else { return nil }
        if let spaceID = userInfo.spaceID, let space = state.space(for: spaceID) {
            return space
        }
        if let dataStoreID = userInfo.dataStoreID {
            return state.spaces.first { $0.id == dataStoreID && $0.dataStoreMode == .separate }
        }
        return sharedDataStoreSpace()
    }

    /// The space whose pages use `dataStore`.
    private func space(using dataStore: WKWebsiteDataStore) -> Space? {
        guard dataStore.isPersistent else { return nil }
        if dataStore === WKWebsiteDataStore.default() {
            return sharedDataStoreSpace()
        }
        guard let identifier = dataStore.identifier else { return nil }
        return pagePool?.state.spaces.first { $0.id == identifier && $0.dataStoreMode == .separate }
    }

    /// A space on the shared data store: the frontmost window's when it is one, else the first.
    private func sharedDataStoreSpace() -> Space? {
        guard let pagePool else { return nil }
        if let active = pagePool.windowManager?.activeWindowController?.windowState.activeSpace,
           active.dataStoreMode == .global {
            return active
        }
        return pagePool.state.spaces.first { $0.dataStoreMode == .global }
    }

    /// The persistent data store with `id`: a separate space's, or the shared one for nil.
    private func dataStore(withID id: UUID?) -> WKWebsiteDataStore? {
        guard let id else { return .default() }
        return pagePool?.spaceDataStoreManager?.dataStore(forSpaceID: id)
    }
}

// MARK: - Engine Notifications

extension WebNotificationManager {
    /// A notification an engine page showed.
    func show(_ notification: EngineNotification, from page: WebPage) {
        guard let origin = WebOrigin(url: notification.origin) else { return }
        let tab = page.tabPage.tab
        let incoming = IncomingWebNotification(
            source: .engine(pageID: page.tabPage.id, identifier: notification.id),
            origin: origin,
            title: notification.title,
            body: notification.body,
            tag: notification.tag.flatMap { $0.isEmpty ? nil : $0 },
            iconURL: notification.iconURL,
            isSilent: notification.isSilent,
            isPersistent: false,
            tabPageID: page.tabPage.id,
            tabID: tab?.id,
            spaceID: tab?.space?.id,
            dataStoreID: nil,
            persistentRepresentation: nil,
        )
        deliver(incoming) {}
    }

    /// An engine page closed a notification it showed.
    func withdrawEngineNotification(_ id: String, from page: WebPage) {
        withdraw([.engine(pageID: page.tabPage.id, identifier: id)])
    }
}
