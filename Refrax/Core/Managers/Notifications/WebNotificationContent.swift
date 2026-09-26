import Foundation
import UserNotifications

// MARK: - Incoming Notification

/// A notification a page or service worker asked Refrax to show.
nonisolated struct IncomingWebNotification: Hashable, Sendable {
    /// Who to tell when the user clicks or dismisses it.
    nonisolated enum Source: Hashable, Sendable {
        /// A WebKit notification: `identifier` within the manager `managerKey` names.
        case webKit(managerKey: UInt, identifier: UInt64)
        /// A notification from an engine page, by the engine's own ID.
        case engine(pageID: UUID, identifier: String)
        /// A notification an engine reported outside any page (a service worker's), by the engine's own ID.
        case engineHost(engineID: EngineID, identifier: String)
    }

    let source: Source
    let origin: WebOrigin
    let title: String
    let body: String
    /// Nil when the page gave none; a tagged notification replaces the origin's previous one
    /// with the same tag.
    let tag: String?
    let iconURL: URL?
    let isSilent: Bool
    /// Shown by a service worker, so it outlives any one page.
    let isPersistent: Bool
    /// The tab page that showed it; nil for a service worker notification.
    let tabPageID: UUID?
    let tabID: UUID?
    let spaceID: UUID?
    /// The data store of a service worker notification; nil for the default data store.
    let dataStoreID: UUID?
    /// WebKit's description of a service worker notification, for delivering its click after a relaunch.
    let persistentRepresentation: Data?
}

// MARK: - User Info

/// What a delivered web notification carries in `UNNotificationContent.userInfo`, so a click
/// can be routed back to its origin, page, and space, even after Refrax relaunches.
nonisolated struct WebNotificationUserInfo: Hashable, Sendable {
    private nonisolated enum Key {
        static let marker = "refrax.webNotification"
        static let origin = "origin"
        static let notificationID = "notificationID"
        static let tabPageID = "tabPageID"
        static let tabID = "tabID"
        static let spaceID = "spaceID"
        static let dataStoreID = "dataStoreID"
        static let isPersistent = "isPersistent"
        static let persistentRepresentation = "persistentRepresentation"
    }

    let origin: WebOrigin
    /// The notification request's identifier.
    let notificationID: String
    let tabPageID: UUID?
    let tabID: UUID?
    let spaceID: UUID?
    let dataStoreID: UUID?
    let isPersistent: Bool
    let persistentRepresentation: Data?

    init(notification: IncomingWebNotification, notificationID: String) {
        self.origin = notification.origin
        self.notificationID = notificationID
        self.tabPageID = notification.tabPageID
        self.tabID = notification.tabID
        self.spaceID = notification.spaceID
        self.dataStoreID = notification.dataStoreID
        self.isPersistent = notification.isPersistent
        self.persistentRepresentation = notification.persistentRepresentation
    }

    /// Reads a delivered notification's user info; nil for notifications that aren't web notifications.
    init?(_ dictionary: [AnyHashable: Any]) {
        guard dictionary[Key.marker] as? Bool == true,
              let originString = dictionary[Key.origin] as? String,
              let origin = WebOrigin(string: originString),
              let notificationID = dictionary[Key.notificationID] as? String
        else { return nil }
        self.origin = origin
        self.notificationID = notificationID
        self.tabPageID = (dictionary[Key.tabPageID] as? String).flatMap(UUID.init(uuidString:))
        self.tabID = (dictionary[Key.tabID] as? String).flatMap(UUID.init(uuidString:))
        self.spaceID = (dictionary[Key.spaceID] as? String).flatMap(UUID.init(uuidString:))
        self.dataStoreID = (dictionary[Key.dataStoreID] as? String).flatMap(UUID.init(uuidString:))
        self.isPersistent = dictionary[Key.isPersistent] as? Bool ?? false
        self.persistentRepresentation = dictionary[Key.persistentRepresentation] as? Data
    }

    /// Property-list values only, as `userInfo` requires.
    var dictionary: [String: Any] {
        var result: [String: Any] = [
            Key.marker: true,
            Key.origin: origin.string,
            Key.notificationID: notificationID,
            Key.isPersistent: isPersistent,
        ]
        result[Key.tabPageID] = tabPageID?.uuidString
        result[Key.tabID] = tabID?.uuidString
        result[Key.spaceID] = spaceID?.uuidString
        result[Key.dataStoreID] = dataStoreID?.uuidString
        result[Key.persistentRepresentation] = persistentRepresentation
        return result
    }
}

// MARK: - Content

/// Maps a web notification onto a macOS notification request.
nonisolated enum WebNotificationContentBuilder {
    /// Prefix of every web notification's request identifier.
    static let requestPrefix = "refrax.web-notification."

    /// The category web notifications use, so Refrax hears when one is dismissed.
    static let categoryIdentifier = "refrax.web-notification"

    /// The request identifier: stable per origin and tag, so a tagged notification replaces
    /// the previous one; `uniqueID` otherwise.
    static func requestIdentifier(for notification: IncomingWebNotification, uniqueID: UUID) -> String {
        if let tag = notification.tag, !tag.isEmpty {
            return "\(requestPrefix)\(notification.origin.string)#\(tag)"
        }
        return requestPrefix + uniqueID.uuidString
    }

    /// Whether a request identifier belongs to a web notification.
    static func isWebNotification(_ requestIdentifier: String) -> Bool {
        requestIdentifier.hasPrefix(requestPrefix)
    }

    /// Title and body from the page, the site as the subtitle, one thread per origin, and
    /// no sound for a silent notification.
    static func content(for notification: IncomingWebNotification, userInfo: WebNotificationUserInfo) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.origin.displayName
        content.body = notification.body
        content.threadIdentifier = notification.origin.string
        content.categoryIdentifier = categoryIdentifier
        content.sound = notification.isSilent ? nil : .default
        content.userInfo = userInfo.dictionary
        return content
    }
}
