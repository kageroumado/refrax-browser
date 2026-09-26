import Foundation
@testable import Refrax
import SwiftData
import Testing
import UserNotifications
import WebKit

// MARK: - Origins

@Suite("Web notification origins")
struct WebOriginTests {
    @Test("Origins normalize scheme and host case and drop default ports, paths, and queries")
    func normalization() {
        #expect(WebOrigin(string: "HTTPS://Example.COM:443/inbox?x=1#top")?.string == "https://example.com")
        #expect(WebOrigin(string: "http://Example.com:80/")?.string == "http://example.com")
        #expect(WebOrigin(string: "http://localhost:8000/test.html")?.string == "http://localhost:8000")
        #expect(WebOrigin(string: "https://app.example.com:8443")?.string == "https://app.example.com:8443")
        #expect(WebOrigin(string: "  https://example.com  ")?.string == "https://example.com")
    }

    @Test("File pages share one origin; other schemes have none")
    func schemes() {
        #expect(WebOrigin(string: "file:///Users/me/test.html")?.string == "file://")
        #expect(WebOrigin(string: "ftp://example.com") == nil)
        #expect(WebOrigin(string: "about:blank") == nil)
        #expect(WebOrigin(string: "https://") == nil)
    }

    @Test("Display names show the host, the port when not default, and the scheme only for HTTP")
    func displayNames() {
        #expect(WebOrigin(string: "https://mail.example.com")?.displayName == "mail.example.com")
        #expect(WebOrigin(string: "http://localhost:8000")?.displayName == "http://localhost:8000")
        #expect(WebOrigin(string: "file:///tmp/a.html")?.displayName == "Local Files")
    }

    @Test("Site names show the host and the port when not default, never the scheme")
    func siteNames() {
        #expect(WebOrigin(string: "https://mail.example.com")?.siteName == "mail.example.com")
        #expect(WebOrigin(string: "http://localhost:8765")?.siteName == "localhost:8765")
        #expect(WebOrigin(string: "http://example.com:80")?.siteName == "example.com")
        #expect(WebOrigin(string: "file:///tmp/a.html")?.siteName == "Local Files")
    }

    @Test("Origins sort by host, then scheme, then port")
    func ordering() throws {
        let origins = try ["https://b.com", "https://a.com:8443", "http://a.com", "https://a.com"]
            .map { try #require(WebOrigin(string: $0)) }
        #expect(origins.sorted().map(\.string) == [
            "http://a.com", "https://a.com", "https://a.com:8443", "https://b.com",
        ])
    }
}

// MARK: - Permission Store

@Suite("Web notification permissions", .serialized)
@MainActor
struct WebNotificationPermissionStoreTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func origin(_ string: String) throws -> WebOrigin {
        try #require(WebOrigin(string: string))
    }

    @Test("A decision is stored, changed, and reported in WebKit's permission map")
    func grantAndDeny() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let store = WebNotificationPermissionStore(modelContext: container.mainContext)
        let site = try origin("https://chat.example.com")

        #expect(store.state(for: site) == nil)
        store.setState(.granted, for: site)
        #expect(store.state(for: site) == .granted)
        #expect(store.permissionMap == ["https://chat.example.com": true])

        store.setState(.denied, for: site)
        #expect(store.state(for: site) == .denied)
        #expect(store.permissionMap == ["https://chat.example.com": false])
        #expect(store.records.count == 1)
    }

    @Test("Records list by host and survive a new store on the same context")
    func listingAndReload() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let store = WebNotificationPermissionStore(modelContext: container.mainContext)
        for string in ["https://zulip.example", "https://alpha.example", "http://mid.example:8080"] {
            store.setState(.granted, for: try origin(string))
        }
        #expect(store.records.map(\.origin) == ["https://alpha.example", "http://mid.example:8080", "https://zulip.example"])

        let reloaded = WebNotificationPermissionStore(modelContext: container.mainContext)
        #expect(reloaded.records.map(\.origin) == store.records.map(\.origin))
    }

    @Test("Removing forgets the origin, so it asks again")
    func removal() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let store = WebNotificationPermissionStore(modelContext: container.mainContext)
        let first = try origin("https://one.example")
        let second = try origin("https://two.example")
        store.setState(.granted, for: first)
        store.setState(.denied, for: second)

        store.remove([first])
        #expect(store.state(for: first) == nil)
        #expect(store.state(for: second) == .denied)

        store.removeAll()
        #expect(store.records.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WebNotificationPermission>()) == 0)
    }

    @Test("Shown notifications are counted for allowed origins only")
    func statistics() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let store = WebNotificationPermissionStore(modelContext: container.mainContext)
        let site = try origin("https://news.example")
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        store.recordNotification(from: site, at: date)
        #expect(store.record(for: site) == nil)

        store.setState(.granted, for: site)
        store.recordNotification(from: site, at: date)
        store.recordNotification(from: site, at: date)
        #expect(store.record(for: site)?.notificationCount == 2)
        #expect(store.record(for: site)?.lastNotificationAt == date)
    }
}

// MARK: - Asking

@Suite("Web notification requests", .serialized)
@MainActor
struct WebNotificationRequestTests {
    private func makeManager() throws -> (ModelContainer, WebNotificationManager, BrowserSettings) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let settings = BrowserSettings.fetchOrCreate(in: container.mainContext)
        return (container, WebNotificationManager(modelContext: container.mainContext, settings: settings), settings)
    }

    @Test("Private spaces are denied without asking and nothing is stored")
    func privateSpaces() async throws {
        let (container, manager, _) = try makeManager()
        defer { withExtendedLifetime(container) {} }
        let prompts = PagePrompts()
        let site = try #require(WebOrigin(string: "https://chat.example.com"))

        #expect(await manager.requestPermission(for: site, isPrivate: true, prompts: prompts) == false)
        #expect(prompts.current == nil)
        #expect(manager.permissions.isEmpty)
        #expect(manager.store.state(for: site) == nil)
    }

    @Test("With asking turned off, requests are denied silently and not remembered")
    func askingOff() async throws {
        let (container, manager, settings) = try makeManager()
        defer { withExtendedLifetime(container) {} }
        settings.allowWebsiteNotificationRequests = false
        let prompts = PagePrompts()
        let site = try #require(WebOrigin(string: "https://chat.example.com"))

        #expect(await manager.requestPermission(for: site, isPrivate: false, prompts: prompts) == false)
        #expect(prompts.current == nil)
        #expect(manager.store.state(for: site) == nil)
    }

    @Test("Don't Allow is remembered; a dismissed prompt is not")
    func declining() async throws {
        let (container, manager, _) = try makeManager()
        defer { withExtendedLifetime(container) {} }
        let prompts = PagePrompts()
        let site = try #require(WebOrigin(string: "https://chat.example.com"))

        let dismissed = Task { await manager.requestPermission(for: site, isPrivate: false, prompts: prompts) }
        await Task.yield()
        #expect(prompts.current?.question == .permission(kind: .notifications, origin: "chat.example.com"))
        prompts.dismissAll()
        #expect(await dismissed.value == false)
        #expect(manager.store.state(for: site) == nil)

        let declined = Task { await manager.requestPermission(for: site, isPrivate: false, prompts: prompts) }
        await Task.yield()
        prompts.answer(.declineAndRemember)
        #expect(await declined.value == false)
        #expect(manager.store.state(for: site) == .denied)
        #expect(manager.permissionDecision(for: site, isPrivate: false) == .deny)

        // A remembered answer is given without asking again.
        #expect(await manager.requestPermission(for: site, isPrivate: false, prompts: prompts) == false)
        #expect(prompts.current == nil)
    }
}

// MARK: - Content

@Suite("Web notification content")
@MainActor
struct WebNotificationContentTests {
    private func notification(tag: String? = nil, silent: Bool = false, origin: String = "https://chat.example.com") throws -> IncomingWebNotification {
        IncomingWebNotification(
            source: .webKit(managerKey: 7, identifier: 42),
            origin: try #require(WebOrigin(string: origin)),
            title: "New message",
            body: "Ada: lunch?",
            tag: tag,
            iconURL: nil,
            isSilent: silent,
            isPersistent: false,
            tabPageID: UUID(),
            tabID: UUID(),
            spaceID: UUID(),
            dataStoreID: nil,
            persistentRepresentation: nil,
        )
    }

    @Test("A tag gives a stable identifier per origin, so the next one replaces it")
    func tagIdentifiers() throws {
        let tagged = try notification(tag: "thread-1")
        let first = WebNotificationContentBuilder.requestIdentifier(for: tagged, uniqueID: UUID())
        let second = WebNotificationContentBuilder.requestIdentifier(for: tagged, uniqueID: UUID())
        #expect(first == second)
        #expect(first == "refrax.web-notification.https://chat.example.com#thread-1")

        let otherSite = try notification(tag: "thread-1", origin: "https://other.example")
        #expect(WebNotificationContentBuilder.requestIdentifier(for: otherSite, uniqueID: UUID()) != first)
    }

    @Test("Untagged notifications each get their own identifier")
    func untaggedIdentifiers() throws {
        let untagged = try notification()
        let id = UUID()
        #expect(WebNotificationContentBuilder.requestIdentifier(for: untagged, uniqueID: id) == "refrax.web-notification.\(id.uuidString)")
        #expect(WebNotificationContentBuilder.isWebNotification("refrax.web-notification.\(id.uuidString)"))
        #expect(!WebNotificationContentBuilder.isWebNotification("com.refrax.pagereminder.x"))
    }

    @Test("Content carries title, body, the site as subtitle, one thread per origin, and respects silent")
    func contentMapping() throws {
        let loud = try notification()
        let userInfo = WebNotificationUserInfo(notification: loud, notificationID: "id")
        let content = WebNotificationContentBuilder.content(for: loud, userInfo: userInfo)
        #expect(content.title == "New message")
        #expect(content.body == "Ada: lunch?")
        #expect(content.subtitle == "chat.example.com")
        #expect(content.threadIdentifier == "https://chat.example.com")
        #expect(content.categoryIdentifier == WebNotificationContentBuilder.categoryIdentifier)
        #expect(content.sound != nil)

        let quiet = try notification(silent: true)
        #expect(WebNotificationContentBuilder.content(for: quiet, userInfo: userInfo).sound == nil)

        let local = try notification(origin: "http://localhost:8765")
        #expect(WebNotificationContentBuilder.content(for: local, userInfo: userInfo).subtitle == "localhost:8765")
    }

    @Test("User info round-trips through a property list")
    func userInfoRoundTrip() throws {
        let representation = try #require(WebNotificationManager.encodePersistentRepresentation([
            "WebNotificationTitleKey": "New message",
            "WebNotificationSessionIDKey": 1,
        ]))
        let incoming = IncomingWebNotification(
            source: .webKit(managerKey: 1, identifier: 2),
            origin: try #require(WebOrigin(string: "https://chat.example.com")),
            title: "t",
            body: "b",
            tag: nil,
            iconURL: nil,
            isSilent: false,
            isPersistent: true,
            tabPageID: nil,
            tabID: UUID(),
            spaceID: UUID(),
            dataStoreID: UUID(),
            persistentRepresentation: representation,
        )
        let userInfo = WebNotificationUserInfo(notification: incoming, notificationID: "refrax.web-notification.x")

        let data = try PropertyListSerialization.data(fromPropertyList: userInfo.dictionary, format: .binary, options: 0)
        let decoded = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any])
        #expect(WebNotificationUserInfo(decoded) == userInfo)

        let restored = try #require(userInfo.persistentRepresentation.flatMap(WebNotificationManager.decodePersistentRepresentation))
        #expect(restored["WebNotificationTitleKey"] as? String == "New message")
    }

    @Test("Other notifications' user info isn't read as a web notification")
    func foreignUserInfo() {
        #expect(WebNotificationUserInfo(["pageURL": "https://example.com"]) == nil)
        #expect(WebNotificationUserInfo([:]) == nil)
    }

    @Test("Oversized service worker descriptions are left out")
    func representationCap() {
        let large = String(repeating: "x", count: WebNotificationManager.Constants.maximumPersistentRepresentationBytes + 1)
        #expect(WebNotificationManager.encodePersistentRepresentation(["data": large]) == nil)
    }
}

// MARK: - Engine Contract

@Suite("Engine notification messages")
struct EngineNotificationWireTests {
    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    @Test("notificationShown decodes; a non-web icon URL rejects the event")
    func decoding() throws {
        let event = try EngineWire.decodeEvent(data(
            #"{"notificationShown":{"notification":{"id":"n1","origin":"https://chat.example","title":"Hi","body":"there","tag":"t","iconURL":null,"isSilent":true}}}"#,
        ))
        let origin = try #require(URL(string: "https://chat.example"))
        #expect(event == .notificationShown(notification: EngineNotification(
            id: "n1",
            origin: origin,
            title: "Hi",
            body: "there",
            tag: "t",
            iconURL: nil,
            isSilent: true,
        )))
        #expect(throws: EngineError.self) {
            try EngineWire.decodeEvent(data(
                #"{"notificationShown":{"notification":{"id":"n1","origin":"https://chat.example","title":"Hi","body":"","iconURL":"javascript:alert(1)","isSilent":false}}}"#,
            ))
        }
    }

    @Test("The click command encodes with the engine's ID")
    func commands() throws {
        let clicked = try #require(String(data: EngineWire.encode(PageCommand.notificationClicked(id: "n1")), encoding: .utf8))
        #expect(clicked == #"{"notificationClicked":{"id":"n1"}}"#)
    }
}
