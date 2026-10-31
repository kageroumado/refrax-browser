import AppKit
import Foundation
import Testing
import WebKit
@testable import Refrax

/// Native hosts stop when their output ends, when a message goes unanswered, and when the
/// extension that started them goes away.
@Suite("Native messaging host lifecycle", .tags(.extensionManager), .serialized)
@MainActor
struct NativeMessagingHostLifecycleTests {
    private func host(_ script: String) throws -> (EchoHostFixture, ResolvedNativeMessagingHost) {
        let fixture = try EchoHostFixture(script: script, allowedOrigins: ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"])
        let identity = ExtensionIdentity(
            verifiedChromeID: "abcdefghijklmnopabcdefghijklmnop", claimedChromeID: nil, claimedGeckoID: nil, refraxOrigin: "",
        )
        return try (fixture, fixture.locator.host(named: fixture.name, for: identity))
    }

    private func run(_ script: String) async throws -> (NativeMessagingHostProcess, [NativeMessagingHostProcess.Event]) {
        let (_, resolved) = try host(script)
        var events: [NativeMessagingHostProcess.Event] = []
        let process = NativeMessagingHostProcess(host: resolved) { events.append($0) }
        try process.start()
        try process.send(["ping": 1])
        _ = try await waitFor("the host's output to end") {
            events.contains {
                if case .closed = $0 {
                    true
                } else {
                    false
                }
            } ? true : nil
        }
        _ = try await waitFor("the host to be stopped") { process.hasExited ? true : nil }
        return (process, events)
    }

    @Test
    func `A host that announces an oversized message is stopped`() async throws {
        let (_, events) = try await run(EchoHostFixture.oversizedScript)
        guard case let .closed(error) = events.last else { Issue.record("\(events)"); return }
        #expect(error == .messageTooLarge)
    }

    @Test
    func `A host that closes its output is stopped`() async throws {
        let (_, events) = try await run(EchoHostFixture.closingScript)
        guard case let .closed(error) = events.last else { Issue.record("\(events)"); return }
        #expect(error == .hostExited)
    }

    @Test
    func `A one-off message without a reply times out and stops its host`() async throws {
        let (fixture, _) = try host(EchoHostFixture.silentScript)
        let router = NativeMessagingRouter(locator: fixture.locator)
        router.identity = { _ in
            ExtensionIdentity(verifiedChromeID: "abcdefghijklmnopabcdefghijklmnop", claimedChromeID: nil, claimedGeckoID: nil, refraxOrigin: "")
        }
        router.oneOffTimeout = .milliseconds(300)
        let context = try await ExtensionFixture(files: [
            "manifest.json": #"{"manifest_version": 3, "name": "Silent", "version": "1.0", "permissions": ["nativeMessaging"]}"#,
        ]).makeContext()

        await #expect(throws: NativeMessagingError.timedOut) {
            _ = try await router.send(["ping": 1], to: fixture.name, from: context)
        }
    }

    @Test
    func `Without the nativeMessaging permission no host starts`() async throws {
        let (fixture, _) = try host(EchoHostFixture.echoScript)
        let router = NativeMessagingRouter(locator: fixture.locator)
        let context = try await ExtensionFixture(files: [
            "manifest.json": #"{"manifest_version": 3, "name": "Plain", "version": "1.0"}"#,
        ]).makeContext()
        await #expect(throws: NativeMessagingError.forbidden) {
            _ = try await router.send(["ping": 1], to: fixture.name, from: context)
        }
    }

    @Test
    func `Disabling an extension ends its ports and stops their hosts`() async throws {
        let (env, _, _, probe) = try ExtensionAPIFixtureTests.environment()
        let host = try EchoHostFixture(allowedExtensions: ["echo@refrax.test"])
        let router = env.extensionManager.nativeMessaging
        router.locator = host.locator
        router.storedConsent = { _, _ in true }
        let folder = try ExtensionAPIFixtureTests.persistentBackground(permissions: [], script: """
        const port = browser.runtime.connectNative("\(host.name)");
        port.onMessage.addListener(() => probe({ kind: "open" }));
        port.postMessage({ ping: 1 });
        """, extra: #", "browser_specific_settings": {"gecko": {"id": "echo@refrax.test"}}"#).write()
        let installed = try await env.extensionManager.installFromFolder(folder)
        _ = try await probe.message(kind: "open")
        #expect(router.connectionCount == 1)

        try await env.extensionManager.disable(installed)

        #expect(router.connectionCount == 0)
        try await env.extensionManager.uninstall(installed)
    }

    @Test
    func `A host in Refrax's folder knows an installation by one origin, from any space`() async throws {
        let (env, _, _, _) = try ExtensionAPIFixtureTests.environment()
        let manager = env.extensionManager
        let folder = try ExtensionAPIFixtureTests.persistentBackground(permissions: [], script: "").write()
        let installed = try await manager.installFromFolder(folder)
        let defaultContext = try #require(manager.context(for: installed))
        let origin = ExtensionContextIdentifier.baseURL(
            for: ExtensionContextIdentifier.identifier(installedID: installed.uniqueIdentifier, spaceID: nil),
        ).absoluteString
        let own = try EchoHostFixture(allowedOrigins: [origin])
        manager.nativeMessaging.locator = NativeMessagingHostLocator(refraxDirectory: own.directory, browserDirectories: [])

        let space = env.makeSpace(name: "Separate")
        space.dataStoreMode = .separate
        let isolated = manager.controller(for: space)
        let isolatedContext = try await waitFor("the extension in the space's controller") {
            isolated.extensionContexts.first { manager.installedExtension(for: $0)?.id == installed.id }
        }
        #expect(isolatedContext.baseURL != defaultContext.baseURL)

        let reply = try await manager.nativeMessaging.send(["ping": 3], to: own.name, from: isolatedContext)
        #expect(((reply as? [String: Any])?["argv"] as? [String]) == [origin])

        try await manager.uninstall(installed)
    }
}

/// Extensions act only within their own controller, private storage ends with its
/// controller, and installations keep their identity through updates.
@Suite("Extension isolation", .tags(.extensionManager), .serialized)
@MainActor
struct ExtensionIsolationTests {
    private static let counter = """
    browser.storage.local.get("count").then(async (stored) => {
        const count = (stored.count || 0) + 1;
        await browser.storage.local.set({ count });
        probe({ kind: "count-" + count });
    });
    """

    @Test
    func `A private space's extension storage ends with its controller`() async throws {
        let (env, _, _, probe) = try ExtensionAPIFixtureTests.environment()
        let manager = env.extensionManager
        let space = env.makeSpace(name: "Private")
        space.dataStoreMode = .private
        let fixture = ExtensionAPIFixtureTests.persistentBackground(permissions: ["storage"], script: Self.counter)
        let installedID = UUID().uuidString

        let first = manager.controller(for: space)
        #expect(!first.configuration.isPersistent)
        let firstContext = try await fixture.makeContext(installedID: installedID, spaceID: space.id)
        try first.load(firstContext)
        try await firstContext.loadBackgroundContent()
        _ = try await probe.message(kind: "count-1")
        manager.removeController(for: space)
        try first.unload(firstContext)

        let second = manager.controller(for: space)
        #expect(second !== first)
        let secondContext = try await fixture.makeContext(installedID: installedID, spaceID: space.id)
        try second.load(secondContext)
        try await secondContext.loadBackgroundContent()
        _ = try await waitFor("the second count") {
            probe.messages.count(where: { $0["kind"] as? String == "count-1" }) == 2 ? true : nil
        }
        #expect(!probe.messages.contains { $0["kind"] as? String == "count-2" })
    }

    @Test
    func `A default-controller extension creates tabs and windows only in its own spaces`() async throws {
        let (env, space, windowState, probe) = try ExtensionAPIFixtureTests.environment()
        let separate = env.makeSpace(name: "Separate")
        separate.dataStoreMode = .separate
        let privateSpace = env.makeSpace(name: "Private")
        privateSpace.dataStoreMode = .private
        env.spaceManager.switchToSpaceSync(separate, for: windowState)

        _ = try await ExtensionAPIFixtureTests.persistentBackground(permissions: [], script: """
        browser.tabs.create({ url: "https://example.com/created" })
            .then(() => probe({ kind: "tab" }), (error) => probe({ kind: "tab", error: String(error) }));
        browser.windows.create({ incognito: true, url: "https://example.com/private" })
            .then(() => probe({ kind: "window" }), (error) => probe({ kind: "window", error: String(error) }));
        """).load(into: env)

        _ = try await probe.message(kind: "tab")
        let window = try await probe.message(kind: "window")
        #expect(window["error"] != nil, "\(window)")
        let created = { (tab: Refrax.Tab) in tab.activePage.url.path() == "/created" }
        #expect(space.tabs.contains(where: created))
        #expect(!separate.tabs.contains(where: created))
        #expect(privateSpace.tabs.isEmpty)
    }

    @Test
    func `Shim APIs refuse an extension without their permission`() async throws {
        let (env, _, _, probe) = try ExtensionAPIFixtureTests.environment()
        _ = try await ExtensionAPIFixtureTests.persistentBackground(permissions: [], script: """
        webkit.messageHandlers.refraxShim.postMessage({ api: "idle", method: "queryState", args: {} })
            .then((reply) => probe({ kind: "idle", reply }), (error) => probe({ kind: "idle", error: String(error) }));
        webkit.messageHandlers.refraxShim.postMessage({ api: "downloads", method: "search", args: {} })
            .then((reply) => probe({ kind: "downloads", reply }), (error) => probe({ kind: "downloads", error: String(error) }));
        """).load(into: env)

        for kind in ["idle", "downloads"] {
            let answer = try await probe.message(kind: kind)
            #expect(answer["reply"] == nil, "\(answer)")
            #expect((answer["error"] as? String)?.contains("Permission denied") == true, "\(answer)")
        }
    }

    private static let reservedCommands = """
    , "commands": {
        "quit": {"suggested_key": {"default": "Ctrl+Q"}, "description": "Quit"},
        "close": {"suggested_key": {"default": "Ctrl+W"}, "description": "Close"}
    }
    """

    @Test
    func `A command on Quit's keys, or keys macOS keeps, never runs`() async throws {
        let (env, _, windowState, probe) = try ExtensionAPIFixtureTests.environment()
        let context = try await ExtensionAPIFixtureTests.persistentBackground(permissions: [], script: """
        browser.commands.onCommand.addListener((command) => probe({ kind: "command", command }));
        probe({ kind: "ready" });
        """, extra: Self.reservedCommands).load(into: env)
        _ = try await probe.message(kind: "ready")

        let menu = NSMenu()
        let appItem = NSMenuItem(title: "Refrax", action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(NSMenuItem(title: "Quit Refrax", action: nil, keyEquivalent: "q"))
        menu.addItem(appItem)
        let handler = ExtensionCommandHandler(extensionManager: env.extensionManager, mainMenu: { menu })

        let quit = try #require(context.commands.first { $0.id == "quit" })
        let close = try #require(context.commands.first { $0.id == "close" })
        #expect(handler.conflict(for: quit) == "Quit Refrax")
        #expect(handler.conflict(for: close) == "macOS")

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: quit.modifierFlags, timestamp: 0, windowNumber: 0,
            context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12,
        ))
        #expect(!handler.perform(event, in: windowState))
        try await Task.sleep(for: .milliseconds(300))
        #expect(!probe.messages.contains { $0["kind"] as? String == "command" })
    }

    @Test
    func `Two folders with the same name install as two extensions`() async throws {
        let (env, _, _, _) = try ExtensionAPIFixtureTests.environment()
        let manager = env.extensionManager
        var installed: [InstalledExtension] = []
        for _ in 0 ..< 2 {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let folder = parent.appendingPathComponent("extension", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: ExtensionAPIFixtureTests.persistentBackground(permissions: [], script: "").write(), to: folder)
            try await installed.append(manager.installFromFolder(folder))
        }
        #expect(installed[0].uniqueIdentifier != installed[1].uniqueIdentifier)
        let contexts = installed.compactMap { manager.context(for: $0) }
        #expect(contexts.count == 2)
        #expect(contexts.first !== contexts.last)
        for extension_ in installed {
            try await manager.uninstall(extension_)
        }
    }

    /// An extension folder with the storage counter at `version`.
    private func counterFolder(version: String) throws -> URL {
        try ExtensionFixture(files: [
            "manifest.json": """
            {"manifest_version": 2, "name": "Updating", "version": "\(version)", "description": "Updating",
             "permissions": ["storage", "nativeMessaging"],
             "background": {"scripts": ["background.js"], "persistent": true}}
            """,
            "background.js": ExtensionAPIFixtureTests.probe + "\n" + Self.counter,
        ]).write()
    }

    private func archive(_ data: Data, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    @Test
    func `An update keeps the installation's identity and storage`() async throws {
        let (env, _, _, probe) = try ExtensionAPIFixtureTests.environment()
        let manager = env.extensionManager
        let first = try archive(TestArchives.zip(counterFolder(version: "1.0")), named: "updating.xpi")
        let installed = try await manager.installFromArchive(first)
        _ = try await probe.message(kind: "count-1")
        let identifier = try #require(manager.context(for: installed)).uniqueIdentifier

        let second = try archive(TestArchives.zip(counterFolder(version: "2.0")), named: "updating.xpi")
        try await manager.update(installed, from: second)

        _ = try await probe.message(kind: "count-2")
        let updated = try #require(manager.installedExtensions.first { $0.id == installed.id })
        #expect(updated.uniqueIdentifier == installed.uniqueIdentifier)
        #expect(updated.version == "2.0")
        #expect(manager.context(for: updated)?.uniqueIdentifier == identifier)
        try await manager.uninstall(updated)
    }

    @Test
    func `A signed extension accepts only an update signed for the same ID`() async throws {
        let (env, _, _, probe) = try ExtensionAPIFixtureTests.environment()
        let manager = env.extensionManager
        let zip = try TestArchives.zip(counterFolder(version: "1.0"))
        let developer = try TestArchives.rsaSigner()
        let installed = try await manager.installFromArchive(
            archive(TestArchives.crx(zip: zip, developer: developer, signers: [developer]), named: "signed.crx"),
        )
        _ = try await probe.message(kind: "count-1")
        #expect(installed.verifiedChromeID == ExtensionIdentity.chromeID(forPublicKey: developer.spki))

        let impostor = try TestArchives.rsaSigner()
        let update = try archive(
            TestArchives.crx(zip: TestArchives.zip(counterFolder(version: "2.0")), developer: impostor, signers: [impostor]),
            named: "signed.crx",
        )
        await #expect(throws: ExtensionError.invalidSignature) {
            try await manager.update(installed, from: update)
        }
        #expect(manager.installedExtensions.first { $0.id == installed.id }?.version == "1.0")
        try await manager.uninstall(installed)
    }
}
