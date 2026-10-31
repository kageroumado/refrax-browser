import AppKit
import Foundation
import Testing
import WebKit
@testable import Refrax

/// Small fixture extensions that exercise each extension API Refrax implements or wires up,
/// loaded into the unit-test host's WebKit. Their backgrounds report through the in-process
/// native host ``ProbeHost``.
@Suite("Extension APIs with fixture extensions", .tags(.extensionManager), .serialized)
@MainActor
struct ExtensionAPIFixtureTests {
    /// `probe(message)` in a fixture background sends `message` to the probe host.
    private static let probe = """
    function probe(message) {
        return browser.runtime.sendNativeMessage("\(ProbeHost.name)", message);
    }
    """

    private static func persistentBackground(
        permissions: [String],
        script: String,
        extra: String = "",
    ) -> ExtensionFixture {
        let permissionList = (permissions + ["nativeMessaging"]).map { "\"\($0)\"" }.joined(separator: ", ")
        return ExtensionFixture(files: [
            "manifest.json": """
            {"manifest_version": 2, "name": "Fixture", "version": "1.0", "description": "Fixture",
             "permissions": [\(permissionList)],
             "background": {"scripts": ["background.js"], "persistent": true}\(extra)}
            """,
            "background.js": probe + "\n" + script,
        ])
    }

    private func environment() throws -> (TabManagerTestEnvironment, Space, WindowState, ProbeHost) {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        return (env, space, windowState, ProbeHost(router: env.extensionManager.nativeMessaging))
    }

    // MARK: - Actions

    @Test
    func `Badge text, title and enabled state reach the action board, per tab`() async throws {
        let (env, space, _, probe) = try environment()
        let fixture = ExtensionFixture(files: [
            "manifest.json": """
            {"manifest_version": 3, "name": "Badge", "version": "1.0",
             "permissions": ["nativeMessaging", "tabs"],
             "action": {"default_title": "Badge"},
             "background": {"service_worker": "background.js"}}
            """,
            "background.js": Self.probe + """
            
            browser.tabs.onCreated.addListener(async (tab) => {
                await browser.action.setBadgeText({ tabId: tab.id, text: "T" });
                probe({ kind: "tab-badge" });
            });
            (async () => {
                await browser.action.setBadgeText({ text: "7" });
                await browser.action.setTitle({ title: "Seven" });
                await browser.action.disable();
                probe({ kind: "ready" });
            })();
            """,
        ])
        let context = try await fixture.load(into: env)
        _ = try await probe.message(kind: "ready")

        let board = env.extensionManager.actions
        let defaultAppearance = try await waitFor("the default action's badge") {
            board.board.appearance(contextID: context.uniqueIdentifier, tabPageID: nil).flatMap { $0.badgeText == "7" ? $0 : nil }
        }
        #expect(defaultAppearance.label == "Seven")
        #expect(!defaultAppearance.isEnabled)
        #expect(defaultAppearance.hasUnreadBadgeText)

        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: false, loadImmediately: false)
        _ = try await probe.message(kind: "tab-badge")
        let tabPageID = try #require(tab.pages.first?.id)
        _ = try await waitFor("the tab's own badge") {
            board.board.appearance(contextID: context.uniqueIdentifier, tabPageID: tabPageID).flatMap { $0.badgeText == "T" ? $0 : nil }
        }
        #expect(env.extensionManager.actionEntries(for: tab).first?.appearance.badgeText == "T")
        #expect(env.extensionManager.hasUnreadActionBadge(in: tab))

        env.extensionManager.markActionBadgesRead(in: tab)
        #expect(!env.extensionManager.hasUnreadActionBadge(in: tab))

        env.extensionManager.dispatchTabClosed(tab, windowClosing: false)
        #expect(board.board.appearance(contextID: context.uniqueIdentifier, tabPageID: tabPageID)?.badgeText == "7")
    }

    // MARK: - Native messaging

    /// A background that sends one message to `host`, and posts one over a port.
    private static func nativeMessagingFixture(host: String) -> ExtensionFixture {
        persistentBackground(permissions: [], script: """
        browser.runtime.sendNativeMessage("\(host)", { ping: 1 })
            .then((reply) => probe({ kind: "send", reply }), (error) => probe({ kind: "send", error: String(error) }));
        browser.runtime.sendNativeMessage("refrax.test.missing", { ping: 0 })
            .then(() => probe({ kind: "missing" }), (error) => probe({ kind: "missing", error: String(error) }));
        const port = browser.runtime.connectNative("\(host)");
        port.onMessage.addListener((reply) => {
            probe({ kind: "port", reply });
            port.disconnect();
        });
        port.onDisconnect.addListener(() => probe({ kind: "port-closed" }));
        port.postMessage({ ping: 2 });
        """, extra: #", "browser_specific_settings": {"gecko": {"id": "echo@refrax.test"}}"#)
    }

    @Test
    func `One-off messages and ports reach a native host the user allowed, and come back`() async throws {
        let (env, _, _, probe) = try environment()
        let host = try EchoHostFixture(allowedExtensions: ["echo@refrax.test"])
        let router = env.extensionManager.nativeMessaging
        router.locator = host.locator
        var asked: [NativeMessagingRouter.ConsentRequest] = []
        router.storedConsent = { request, _ in
            asked.append(request)
            return true
        }
        _ = try await Self.nativeMessagingFixture(host: host.name).load(into: env)

        let send = try await probe.message(kind: "send")
        let reply = try #require(send["reply"] as? [String: Any], "\(send)")
        #expect((reply["echo"] as? [String: Int]) == ["ping": 1])
        #expect((reply["argv"] as? [String])?.last == "echo@refrax.test")

        let port = try await probe.message(kind: "port")
        #expect(((port["reply"] as? [String: Any])?["echo"] as? [String: Int]) == ["ping": 2], "\(port)")

        let missing = try await probe.message(kind: "missing")
        #expect((missing["error"] as? String)?.isEmpty == false)

        _ = try await waitFor("the port to close") {
            router.connectionCount == 0 ? true : nil
        }
        #expect(asked.first?.hostName == host.name)
        #expect(asked.first?.executablePath == host.executable.resolvingSymlinksInPath().path)
    }

    @Test
    func `A host reached by a claimed identity starts only after the user allows it`() async throws {
        let (env, _, _, probe) = try environment()
        let host = try EchoHostFixture(allowedExtensions: ["echo@refrax.test"])
        let router = env.extensionManager.nativeMessaging
        router.locator = host.locator
        var questions = 0
        router.askConsent = { _, _ in
            questions += 1
            return false
        }
        _ = try await Self.nativeMessagingFixture(host: host.name).load(into: env)

        let send = try await probe.message(kind: "send")
        #expect(send["reply"] == nil)
        #expect((send["error"] as? String)?.isEmpty == false, "\(send)")
        _ = try await probe.message(kind: "port-closed")
        #expect(probe.messages.contains { $0["kind"] as? String == "port" } == false)
        _ = try await waitFor("both questions") { questions == 2 ? true : nil }
        #expect(router.connectionCount == 0)
    }

    @Test
    func `The refrax API answers what the installed extension was granted, in its own spaces`() async throws {
        let (env, space, _, probe) = try environment()
        let privateSpace = env.makeSpace(name: "Private")
        privateSpace.dataStoreMode = .private
        let separateSpace = env.makeSpace(name: "Separate")
        separateSpace.dataStoreMode = .separate
        let folder = try Self.persistentBackground(permissions: ["refrax.spaces"], script: """
        browser.refrax.spaces.getAll()
            .then((spaces) => probe({ kind: "spaces", spaces }), (error) => probe({ kind: "spaces", error: String(error) }));
        browser.refrax.tabs.getFavorites()
            .then(() => probe({ kind: "favorites" }), (error) => probe({ kind: "favorites", error: String(error) }));
        """).write()
        let installed = try await env.extensionManager.installFromFolder(folder)
        defer {
            Task { try? await env.extensionManager.uninstall(installed) }
        }

        let spaces = try await probe.message(kind: "spaces")
        let ids = Set((spaces["spaces"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? [])
        #expect(ids.contains(space.id.uuidString), "\(spaces)")
        #expect(!ids.contains(privateSpace.id.uuidString))
        #expect(!ids.contains(separateSpace.id.uuidString))

        let favorites = try await probe.message(kind: "favorites")
        #expect((favorites["error"] as? String)?.contains("refrax.tabs") == true, "\(favorites)")
    }

    @Test
    func `The refrax API answers nothing to an extension that is not installed`() async throws {
        let (env, _, _, probe) = try environment()
        _ = try await Self.persistentBackground(permissions: ["refrax.spaces"], script: """
        browser.refrax.spaces.getAll()
            .then((spaces) => probe({ kind: "spaces", spaces }), (error) => probe({ kind: "spaces", error: String(error) }));
        """).load(into: env)

        let spaces = try await probe.message(kind: "spaces")
        #expect(spaces["spaces"] == nil)
        #expect((spaces["error"] as? String)?.isEmpty == false)
    }

    // MARK: - Idle

    @Test
    func `idle reports a locked screen to the extension, and active once it unlocks`() async throws {
        let (env, _, _, probe) = try environment()
        let lockNotifications = NotificationCenter()
        env.extensionManager.shimInjector.idleShim.monitor = IdleMonitor(
            lockNotifications: lockNotifications,
            workspaceNotifications: NotificationCenter(),
            idleSeconds: { 0 },
            isLocked: false,
        )
        _ = try await Self.persistentBackground(permissions: ["idle"], script: """
        browser.idle.onStateChanged.addListener((state) => probe({ kind: "idle-" + state }));
        browser.idle.queryState(60).then((state) => probe({ kind: "initial", state }));
        """).load(into: env)

        let initial = try await probe.message(kind: "initial")
        #expect(initial["state"] as? String == "active")
        try await Task.sleep(for: .milliseconds(500))

        lockNotifications.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        _ = try await probe.message(kind: "idle-locked")

        lockNotifications.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        _ = try await probe.message(kind: "idle-active")
    }

    @Test
    func `idle reports idle once input stops for the detection interval`() {
        var seconds: TimeInterval = 10
        let monitor = IdleMonitor(
            lockNotifications: NotificationCenter(),
            workspaceNotifications: NotificationCenter(),
            idleSeconds: { seconds },
            isLocked: false,
        )
        #expect(monitor.state(detectionInterval: 60) == .active)
        seconds = 61
        #expect(monitor.state(detectionInterval: 60) == .idle)
    }

    // MARK: - Commands

    @Test
    func `A command's keys reach commands.onCommand through the shortcut handler`() async throws {
        let (env, _, windowState, probe) = try environment()
        let fixture = Self.persistentBackground(permissions: [], script: """
        browser.commands.onCommand.addListener((command) => probe({ kind: "command", command }));
        probe({ kind: "ready" });
        """, extra: #", "commands": {"refrax-test": {"suggested_key": {"default": "Ctrl+Shift+Y"}, "description": "Test"}}"#)
        let context = try await fixture.load(into: env)
        _ = try await probe.message(kind: "ready")

        let command = try #require(context.commands.first { $0.id == "refrax-test" })
        let key = try #require(command.activationKey)
        let handler = ExtensionCommandHandler(extensionManager: env.extensionManager)
        func keyDown(_ characters: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 16,
            ))
        }

        #expect(try !handler.perform(keyDown(key, [.option]), in: windowState))
        #expect(try handler.perform(keyDown(key, command.modifierFlags), in: windowState))

        let fired = try await probe.message(kind: "command")
        #expect(fired["command"] as? String == "refrax-test")
    }

    // MARK: - Navigation, cookies, network rules

    private func server(_ responses: [String: LoopbackHTTPServer.Response]) async throws -> LoopbackHTTPServer {
        let server = try LoopbackHTTPServer(responses: responses)
        try await server.start()
        return server
    }

    @Test
    func `webNavigation reports a tab's navigation`() async throws {
        let (env, space, _, probe) = try environment()
        let server = try await server(["/page.html": .init(contentType: "text/html", body: "<!doctype html><title>Page</title>")])
        defer { server.stop() }
        let fixture = Self.persistentBackground(permissions: ["webNavigation", "<all_urls>"], script: """
        for (const name of ["onBeforeNavigate", "onCommitted", "onCompleted"]) {
            browser.webNavigation[name].addListener((details) => {
                if (details.url.includes("/page.html")) {
                    probe({ kind: name, url: details.url, frameId: details.frameId });
                }
            });
        }
        probe({ kind: "ready" });
        """)
        _ = try await fixture.load(into: env)
        _ = try await probe.message(kind: "ready")

        env.tabManager.createTab(url: server.url("/page.html"), in: space, makeActive: false, loadImmediately: true)

        for name in ["onBeforeNavigate", "onCommitted", "onCompleted"] {
            let event = try await probe.message(kind: name)
            #expect(event["url"] as? String == server.url("/page.html").absoluteString)
            #expect(event["frameId"] as? Int == 0)
        }
    }

    @Test
    func `cookies sets, reads and removes a cookie in the controller's data store`() async throws {
        let (env, _, _, probe) = try environment()
        let fixture = Self.persistentBackground(permissions: ["cookies", "<all_urls>"], script: """
        (async () => {
            const url = "http://127.0.0.1/";
            await browser.cookies.set({ url, name: "refrax_fixture", value: "42" });
            const cookie = await browser.cookies.get({ url, name: "refrax_fixture" });
            await browser.cookies.remove({ url, name: "refrax_fixture" });
            const removed = await browser.cookies.get({ url, name: "refrax_fixture" });
            probe({ kind: "cookies", value: cookie && cookie.value, removed: removed === null });
        })().catch((error) => probe({ kind: "cookies", error: String(error) }));
        """)
        _ = try await fixture.load(into: env)

        let result = try await probe.message(kind: "cookies")
        #expect(result["value"] as? String == "42", "\(result)")
        #expect(result["removed"] as? Bool == true)
    }

    @Test
    func `A declarativeNetRequest rule blocks the request it matches`() async throws {
        let (env, space, _, probe) = try environment()
        let server = try await server([
            "/page.html": .init(contentType: "text/html", body: """
            <!doctype html><script src="/blocked.js"></script><script src="/allowed.js"></script>
            """),
            "/blocked.js": .init(contentType: "text/javascript", body: ""),
            "/allowed.js": .init(contentType: "text/javascript", body: ""),
        ])
        defer { server.stop() }
        let fixture = Self.persistentBackground(permissions: ["declarativeNetRequest", "<all_urls>"], script: """
        browser.declarativeNetRequest.updateDynamicRules({
            removeRuleIds: [1],
            addRules: [{ id: 1, priority: 1, action: { type: "block" },
                         condition: { urlFilter: "blocked.js", resourceTypes: ["script"] } }],
        }).then(() => probe({ kind: "ready" }), (error) => probe({ kind: "ready", error: String(error) }));
        """)
        _ = try await fixture.load(into: env)
        let ready = try await probe.message(kind: "ready")
        #expect(ready["error"] == nil, "\(ready)")

        env.tabManager.createTab(url: server.url("/page.html"), in: space, makeActive: false, loadImmediately: true)

        _ = try await waitFor("the allowed script's request") { server.requestedPaths.contains("/allowed.js") ? true : nil }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!server.requestedPaths.contains("/blocked.js"), "\(server.requestedPaths)")
    }

    // MARK: - Identity and space controllers

    @Test
    func `An extension's storage survives a reload under the same installation`() async throws {
        let (env, _, _, probe) = try environment()
        let fixture = Self.persistentBackground(permissions: ["storage"], script: """
        browser.storage.local.get("count").then(async (stored) => {
            const count = (stored.count || 0) + 1;
            await browser.storage.local.set({ count });
            probe({ kind: "count-" + count });
        });
        """)
        let installedID = UUID().uuidString
        let controller = env.extensionManager.defaultController
        let first = try await fixture.load(into: env, installedID: installedID)
        _ = try await probe.message(kind: "count-1")
        try controller.unload(first)

        let second = try await fixture.load(into: env, installedID: installedID)
        _ = try await probe.message(kind: "count-2")
        #expect(second.uniqueIdentifier == first.uniqueIdentifier)
        #expect(second.baseURL == first.baseURL)

        // Leaves no storage behind in the test host.
        let types = WKWebExtensionController.allExtensionDataTypes
        await withCheckedContinuation { continuation in
            controller.fetchDataRecord(ofTypes: types, for: second) { record in
                guard let record else { return continuation.resume() }
                controller.removeData(ofTypes: types, from: [record]) {
                    continuation.resume()
                }
            }
        }
    }

    @Test
    func `A separate space's tabs and pages belong to that space's controller`() async throws {
        let (env, _, _, _) = try environment()
        let space = env.makeSpace(name: "Separate")
        space.dataStoreMode = .separate
        let controller = env.extensionManager.controller(for: space)
        #expect(controller !== env.extensionManager.defaultController)
        #expect(env.extensionManager.allControllers.contains { $0 === controller })

        let context = try await ExtensionFixture(files: [
            "manifest.json": #"{"manifest_version": 3, "name": "Isolated", "version": "1.0"}"#,
        ]).makeContext()
        try controller.load(context)

        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: false, loadImmediately: false)
        let tabPage = try #require(tab.pages.first)
        let adapter = env.extensionManager.extensionTab(for: tabPage, pagePool: env.pagePool)
        #expect(context.openTabs.contains(AnyHashable(adapter)))

        let page = try #require(env.pagePool.page(for: tabPage))
        #expect(page.webKitView.configuration.webExtensionController === controller)
    }

    @Test
    func `A window belongs to its space's controller, moves with the space, and refuses others`() async throws {
        let (env, space, windowState, _) = try environment()
        let separateSpace = env.makeSpace(name: "Separate")
        separateSpace.dataStoreMode = .separate
        let manager = env.extensionManager
        let isolated = manager.controller(for: separateSpace)
        let manifest = #"{"manifest_version": 3, "name": "Windows", "version": "1.0"}"#
        let defaultContext = try await ExtensionFixture(files: ["manifest.json": manifest]).makeContext()
        try manager.defaultController.load(defaultContext)
        let isolatedContext = try await ExtensionFixture(files: ["manifest.json": manifest]).makeContext()
        try isolated.load(isolatedContext)

        let nsWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        nsWindow.isReleasedWhenClosed = false
        windowState.window = nsWindow
        #expect(windowState.activeSpace === space)
        manager.dispatchWindowOpened(windowState, nsWindow: nsWindow)
        let window = manager.extensionWindow(for: windowState, nsWindow: nsWindow)

        #expect(defaultContext.openWindows.count == 1)
        #expect(isolatedContext.openWindows.isEmpty)
        try await window.setFrame(CGRect(x: 10, y: 10, width: 400, height: 300), for: defaultContext)
        await #expect(throws: (any Error).self) {
            try await window.setFrame(CGRect(x: 20, y: 20, width: 400, height: 300), for: isolatedContext)
        }

        env.spaceManager.switchToSpaceSync(separateSpace, for: windowState)

        #expect(defaultContext.openWindows.isEmpty)
        #expect(isolatedContext.openWindows.count == 1)
        await #expect(throws: (any Error).self) {
            try await window.close(for: defaultContext)
        }

        manager.dispatchWindowClosed(windowState, nsWindow: nsWindow)
        #expect(isolatedContext.openWindows.isEmpty)
    }
}
