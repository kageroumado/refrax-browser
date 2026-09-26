import Foundation
import WebKit
@testable import Refrax
import Synchronization
import Testing

extension Tag {
    @Tag static var engines: Self
}

// MARK: - Reducer

@Suite("PageReducer", .tags(.engines))
struct PageReducerTests {
    private func reduce(_ events: [PageEvent], from initial: PageSnapshot = PageSnapshot()) -> PageSnapshot {
        events.reduce(into: initial) { PageReducer.reduce(&$0, $1) }
    }

    private let example = URL(string: "https://example.com/")!
    private let other = URL(string: "https://other.example/")!

    @Test("A navigation is pending until it commits")
    func pendingUntilCommit() {
        let state = reduce([.navigationStarted(url: other)], from: PageSnapshot(url: example))
        #expect(state.url == example)
        #expect(state.pendingURL == other)

        let committed = reduce([.navigationCommitted(url: other, isBackForward: false)], from: state)
        #expect(committed.url == other)
        #expect(committed.pendingURL == nil)
    }

    @Test("Commit clears the previous document's decorations")
    func commitClearsDocumentState() {
        let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
        let state = reduce([
            .navigationCommitted(url: example, isBackForward: false),
            .faviconsChanged(urls: [URL(string: "https://example.com/icon.png")!]),
            .themeColorChanged(color: red),
            .hoveredLinkChanged(url: other),
            .navigationFinished(url: example, statusCode: 200),
            .navigationCommitted(url: other, isBackForward: false),
        ])
        #expect(state.faviconURLs.isEmpty)
        #expect(state.themeColor == nil)
        #expect(state.hoveredLink == nil)
        #expect(state.statusCode == nil)
    }

    @Test("A provisional failure is shown; a cancellation is not")
    func failures() {
        let failure = NavigationFailure(
            kind: .cannotFindHost, url: other, isProvisional: true, engineCode: -105, description: "not resolved",
        )
        let failed = reduce([.navigationStarted(url: other), .navigationFailed(failure: failure)])
        #expect(failed.failure == failure)
        #expect(failed.pendingURL == nil)

        let cancelled = NavigationFailure(kind: .cancelled, url: other, isProvisional: true, engineCode: -3, description: "")
        #expect(reduce([.navigationFailed(failure: cancelled)]).failure == nil)

        let recovered = reduce([.navigationStarted(url: example)], from: failed)
        #expect(recovered.failure == nil)
    }

    @Test("A URL change moves the URL without resetting the page")
    func sameDocument() {
        let fragment = URL(string: "https://example.com/#section")!
        let state = reduce([
            .navigationCommitted(url: example, isBackForward: false),
            .titleChanged(title: "Example"),
            .urlChanged(url: fragment),
        ])
        #expect(state.url == fragment)
        #expect(state.title == "Example")
    }

    @Test("Progress is clamped and completes when loading stops")
    func progress() {
        #expect(reduce([.progressChanged(progress: 7)]).progress == 1)
        #expect(reduce([.progressChanged(progress: -1)]).progress == 0)
        let done = reduce([.loadingChanged(isLoading: true), .progressChanged(progress: 0.4), .loadingChanged(isLoading: false)])
        #expect(done.progress == 1)
        #expect(!done.isLoading)
    }

    @Test("Renderer health follows the latest report")
    func rendererHealth() {
        let state = reduce([.rendererHealthChanged(health: .terminated(reason: .crashed))])
        #expect(state.rendererHealth == .terminated(reason: .crashed))
        #expect(reduce([.rendererHealthChanged(health: .running)], from: state).rendererHealth == .running)
    }

    @Test("PageState writes only fields that changed")
    @MainActor
    func observableStateMatchesReducer() {
        let state = PageState()
        let events: [PageEvent] = [
            .navigationStarted(url: example),
            .navigationCommitted(url: example, isBackForward: false),
            .titleChanged(title: "Example"),
            .backForwardChanged(canGoBack: true, canGoForward: false),
            .securityChanged(security: .secure),
        ]
        for event in events {
            state.apply(event)
        }
        #expect(state.snapshot == reduce(events))

        var tracked = false
        withObservationTracking { _ = state.title } onChange: { tracked = true }
        state.apply(.progressChanged(progress: 0.5))
        #expect(!tracked, "A progress event must not invalidate readers of the title")
        state.apply(.titleChanged(title: "Changed"))
        #expect(tracked)
    }
}

// MARK: - Wire format

@Suite("EngineWire", .tags(.engines))
struct EngineWireTests {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test("Decodes the JSON shapes engines emit")
    func decodesEngineEvents() throws {
        #expect(try EngineWire.decodeEvent(data(#"{"titleChanged":{"title":"Hi"}}"#)) == .titleChanged(title: "Hi"))
        #expect(try EngineWire.decodeEvent(data(#"{"navigationCommitted":{"url":"https://a.test/","isBackForward":true}}"#))
            == .navigationCommitted(url: URL(string: "https://a.test/")!, isBackForward: true))
        #expect(try EngineWire.decodeEvent(data(#"{"hoveredLinkChanged":{"url":null}}"#)) == .hoveredLinkChanged(url: nil))
        #expect(try EngineWire.decodeEvent(data(#"{"navigationFinished":{"url":"https://a.test/","statusCode":null}}"#))
            == .navigationFinished(url: URL(string: "https://a.test/")!, statusCode: nil))
        #expect(try EngineWire.decodeEvent(data(#"{"rendererHealthChanged":{"health":{"terminated":{"reason":"crashed"}}}}"#))
            == .rendererHealthChanged(health: .terminated(reason: .crashed)))
        #expect(try EngineWire.decodeEvent(data(#"{"fullscreenChanged":{"state":"active"}}"#)) == .fullscreenChanged(state: .active))
        let failure = try EngineWire.decodeEvent(data(
            #"{"navigationFailed":{"failure":{"kind":"cannotFindHost","url":"https://nope.test/","isProvisional":true,"engineCode":-105,"description":"x"}}}"#,
        ))
        guard case let .navigationFailed(decoded) = failure else {
            Issue.record("Expected a navigation failure")
            return
        }
        #expect(decoded.urlErrorCode == NSURLErrorCannotFindHost)
    }

    @Test("Encodes commands and requests in the documented shape")
    func encodesDocumentedShapes() throws {
        let load = try EngineWire.encode(PageCommand.load(request: URLRequestSpec(url: URL(string: "https://a.test/")!)))
        #expect(String(decoding: load, as: UTF8.self) == #"{"load":{"request":{"headers":{},"url":"https:\/\/a.test\/"}}}"#)
        #expect(String(decoding: try EngineWire.encode(PageCommand.goBack), as: UTF8.self) == #"{"goBack":{}}"#)
        let spec = EnginePageSpec(id: EnginePageID(), profile: .shared, initialURL: nil, opener: nil)
        let object = try JSONSerialization.jsonObject(with: EngineWire.encode(spec)) as? [String: Any]
        #expect((object?["profile"] as? [String: Any])?["shared"] != nil)
        #expect(object?["id"] is String)
    }

    @Test("Encodes policy with the field names the Chromium host reads")
    func encodesPolicy() throws {
        // Engines/Chromium/refrax/host reads these by name; a renamed field silently turns
        // the feature off in Chromium pages.
        let blocking = PolicyUpdate.contentBlocking(policy: ContentBlockingPolicy(
            isEnabled: false,
            lists: [.init(id: "easylist", contents: "||ads.test^")],
            allowlistedHosts: ["a.test"],
        ))
        let blockingObject = try JSONSerialization.jsonObject(with: EngineWire.encode(blocking)) as? [String: Any]
        let policy = (blockingObject?["contentBlocking"] as? [String: Any])?["policy"] as? [String: Any]
        #expect(policy?["isEnabled"] as? Bool == false)
        #expect((policy?["lists"] as? [[String: Any]])?.first?["contents"] as? String == "||ads.test^")
        #expect(policy?["allowlistedHosts"] as? [String] == ["a.test"])

        let script = InjectedScript(
            id: "refrax.test", source: "1", injectionTime: .documentEnd, world: .isolated(name: "w"),
            mainFrameOnly: true, matches: ["*://a.test/*"], excludes: ["*://a.test/x*"], channels: ["c"],
        )
        let scriptsObject = try JSONSerialization.jsonObject(with: EngineWire.encode(PolicyUpdate.scripts(scripts: [script]))) as? [String: Any]
        let encoded = ((scriptsObject?["scripts"] as? [String: Any])?["scripts"] as? [[String: Any]])?.first
        #expect(encoded?["source"] as? String == "1")
        #expect(encoded?["injectionTime"] as? String == "documentEnd")
        #expect(((encoded?["world"] as? [String: Any])?["isolated"] as? [String: Any])?["name"] as? String == "w")
        #expect(encoded?["mainFrameOnly"] as? Bool == true)
        #expect(encoded?["matches"] as? [String] == ["*://a.test/*"])
        #expect(encoded?["excludes"] as? [String] == ["*://a.test/x*"])
        #expect(encoded?["channels"] as? [String] == ["c"])

        let notifications = PolicyUpdate.notifications(policy: NotificationPolicy(
            granted: ["https://a.test"], denied: ["http://b.test:8080"], asksByDefault: false,
        ))
        let notificationsObject = try JSONSerialization.jsonObject(with: EngineWire.encode(notifications)) as? [String: Any]
        let decisions = (notificationsObject?["notifications"] as? [String: Any])?["policy"] as? [String: Any]
        #expect(decisions?["granted"] as? [String] == ["https://a.test"])
        #expect(decisions?["denied"] as? [String] == ["http://b.test:8080"])
        #expect(decisions?["asksByDefault"] as? Bool == false)
    }

    @Test("Decodes engine notification events and encodes their commands")
    func engineNotifications() throws {
        let shown = try EngineWire.decodeEngineEvent(data(#"""
        {"notificationShown":{"profile":{"isolated":{"id":"6F1C2D3E-0000-4000-8000-000000000001"}},
         "notification":{"id":"space-x/p#https://a.test#1","origin":"https://a.test","title":"T","body":"B","isSilent":false}}}
        """#))
        guard case let .notificationShown(profile, notification) = shown else {
            Issue.record("decoded \(shown)")
            return
        }
        #expect(profile == .isolated(id: UUID(uuidString: "6F1C2D3E-0000-4000-8000-000000000001")!))
        #expect(notification.origin == URL(string: "https://a.test"))
        #expect(notification.tag == nil)
        #expect(throws: EngineError.self) {
            try EngineWire.decodeEngineEvent(data(#"""
            {"notificationShown":{"profile":{"shared":{}},
             "notification":{"id":"1","origin":"javascript:alert(1)","title":"","body":"","isSilent":true}}}
            """#))
        }
        let click = try EngineWire.encode(EngineCommand.notificationClicked(id: "n#https://a.test#t"))
        #expect(String(decoding: click, as: UTF8.self) == #"{"notificationClicked":{"id":"n#https:\/\/a.test#t"}}"#)
    }

    @Test("Script values round-trip as plain JSON")
    func scriptValues() throws {
        let value = ScriptValue.object(["a": .array([.number(1), .bool(true), .null, .string("x")])])
        #expect(String(decoding: try EngineWire.encode(value), as: UTF8.self) == #"{"a":[1,true,null,"x"]}"#)
        #expect(try EngineWire.decode(ScriptValue.self, from: data("42")) == .number(42))
        #expect(ScriptValue(foundation: ["k": NSNumber(value: true)]) == .object(["k": .bool(true)]))
    }

    @Test("Rejects oversized messages")
    func oversized() {
        let huge = Data(repeating: UInt8(ascii: " "), count: EngineWire.maximumMessageSize + 1)
        #expect(throws: EngineError.self) { try EngineWire.decodeEvent(huge) }
    }

    @Test("Rejects URLs with schemes an engine may not report")
    func rejectsSchemes() {
        #expect(throws: EngineError.self) {
            try EngineWire.decodeEvent(data(#"{"navigationCommitted":{"url":"javascript:alert(1)","isBackForward":false}}"#))
        }
        #expect(throws: EngineError.self) {
            try EngineWire.decodeRequest(data(#"{"openURL":{"url":"x-apple.systempreferences:","disposition":"popup","userGesture":true}}"#))
        }
    }

    @Test("Clamps numbers and caps strings")
    func clamps() throws {
        #expect(try EngineWire.decodeEvent(data(#"{"zoomChanged":{"factor":1000}}"#)) == .zoomChanged(factor: 10))
        let long = String(repeating: "a", count: EngineWire.maximumStringLength * 2)
        guard case let .titleChanged(title) = try EngineWire.decodeEvent(EngineWire.encode(PageEvent.titleChanged(title: long))) else {
            Issue.record("Expected a title")
            return
        }
        #expect(title.count == EngineWire.maximumStringLength)
    }

    @Test("Rejects unknown message cases")
    func unknownCase() {
        #expect(throws: EngineError.self) { try EngineWire.decodeEvent(data(#"{"formatHardDrive":{}}"#)) }
    }

    @Test("Secret requests carry a plain name; answers carry base64 in the shape the host parses")
    func secretRequests() throws {
        #expect(try EngineWire.decodeEngineRequest(data(#"{"secret":{"name":"storageKey"}}"#)) == .secret(name: "storageKey"))
        for name in ["", "../other", "a b", "ключ", String(repeating: "k", count: 65)] {
            let request = try String(decoding: JSONSerialization.data(withJSONObject: ["secret": ["name": name]]), as: UTF8.self)
            #expect(throws: EngineError.self, "\(name)") { try EngineWire.decodeEngineRequest(data(request)) }
        }
        let answer = try EngineWire.encode(EngineRequestAnswer.secret(value: Data([0xFF, 0x00, 0x7F])))
        #expect(String(decoding: answer, as: UTF8.self) == #"{"secret":{"value":"\/wB\/"}}"#)
        #expect(String(decoding: try EngineWire.encode(EngineRequestAnswer.unavailable), as: UTF8.self) == #"{"unavailable":{}}"#)
    }
}

@Suite("Engine secrets", .tags(.engines))
struct EngineSecretsTests {
    @Test("A secret is created once, stays the same, and goes with its engine's data")
    func lifecycle() throws {
        let engine = EngineID(rawValue: "test.secrets.\(UUID().uuidString)")
        defer { EngineSecrets.removeSecrets(for: engine) }
        let first = try #require(EngineSecrets.secret(named: "storageKey", for: engine))
        #expect(first.count == EngineSecrets.secretSize)
        #expect(EngineSecrets.secret(named: "storageKey", for: engine) == first)
        #expect(EngineSecrets.secret(named: "other", for: engine) != first)

        let neighbor = EngineID(rawValue: "\(engine.rawValue).neighbor")
        defer { EngineSecrets.removeSecrets(for: neighbor) }
        let kept = try #require(EngineSecrets.secret(named: "storageKey", for: neighbor))
        EngineSecrets.removeSecrets(for: engine)
        #expect(EngineSecrets.secret(named: "storageKey", for: engine) != first)
        #expect(EngineSecrets.secret(named: "storageKey", for: neighbor) == kept)
    }
}

// MARK: - Versioning and discovery

@Suite("Engine contract versioning and bundles", .tags(.engines))
struct EngineBundleTests {
    @Test("Accepts same-major engines no newer than Refrax")
    func versioning() {
        let refrax = EngineContractVersion(major: 1, minor: 2)
        #expect(refrax.accepts(EngineContractVersion(major: 1, minor: 0)))
        #expect(refrax.accepts(EngineContractVersion(major: 1, minor: 2)))
        #expect(!refrax.accepts(EngineContractVersion(major: 1, minor: 3)))
        #expect(!refrax.accepts(EngineContractVersion(major: 2, minor: 0)))
    }

    @Test("Capability names parse, ignoring unknown ones")
    func capabilityNames() {
        #expect(EngineCapabilities(names: ["zoom", "devTools", "teleportation"]) == [.zoom, .devTools])
    }

    @Test("Reads an engine bundle's descriptor from its Info.plist")
    func readsDescriptor() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.trashItem(at: root, resultingItemURL: nil) }
        let bundle = root.appending(path: "Test.engine")
        try FileManager.default.createDirectory(at: bundle.appending(path: "Contents"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "test.engine.example",
            "CFBundleShortVersionString": "2.0",
            "NSPrincipalClass": "ExampleEngineHost",
            "RFXEngineContractVersion": "1.0",
            "RFXEngineDisplayName": "Example",
            "RFXEngineVersion": "Example 99",
            "RFXEngineCapabilities": ["zoom"],
            "RFXEngineOutOfProcess": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))

        let parsed = try #require(EngineBundle(url: bundle))
        #expect(parsed.descriptor.id == EngineID(rawValue: "test.engine.example"))
        #expect(parsed.descriptor.displayName == "Example")
        #expect(parsed.descriptor.capabilities == .zoom)
        #expect(parsed.descriptor.isOutOfProcess)
        #expect(parsed.principalClassName == "ExampleEngineHost")
        #expect(throws: EngineError.self) { try parsed.verifySignature() }
    }

    @Test("Ignores bundles without a contract version")
    func ignoresNonEngines() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.trashItem(at: root, resultingItemURL: nil) }
        let bundle = root.appending(path: "NotAnEngine.engine")
        try FileManager.default.createDirectory(at: bundle.appending(path: "Contents"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "not.an.engine", "NSPrincipalClass": "X"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))
        #expect(EngineBundle(url: bundle) == nil)
    }
}

// MARK: - Renderer termination policy

@Suite("Renderer termination policy", .tags(.engines))
struct RendererTerminationPolicyTests {
    @Test("Telemetry slugs never change")
    func telemetrySlugs() {
        let slugs = Dictionary(uniqueKeysWithValues: [
            RendererTerminationReason.exceededMemoryLimit, .exceededCPULimit, .requestedByBrowser, .crashed,
            .sharedProcessCrashed, .unknown,
        ].map { ($0, $0.telemetryReason) })
        #expect(slugs == [
            .exceededMemoryLimit: "oom", .exceededCPULimit: "cpu_limit", .requestedByBrowser: "requested_by_client",
            .crashed: "crash", .sharedProcessCrashed: "shared_process_crash_limit", .unknown: "unknown",
        ])
    }

    @Test("Intentional terminations stay unloaded; crashes recover and count")
    func recoverability() {
        #expect(!RendererTerminationReason.requestedByBrowser.isRecoverable)
        #expect(RendererTerminationReason.exceededMemoryLimit.isRecoverable)
        #expect(!RendererTerminationReason.exceededMemoryLimit.isCrash)
        #expect(RendererTerminationReason.crashed.isCrash)
        #expect(RendererTerminationReason.sharedProcessCrashed.isCrash)
    }

    @Test("WebKit termination reasons map to contract reasons")
    func webKitReasons() {
        #expect(RendererTerminationReason(_WKProcessTerminationReason.crash) == .crashed)
        #expect(RendererTerminationReason(_WKProcessTerminationReason.exceededMemoryLimit) == .exceededMemoryLimit)
        #expect(RendererTerminationReason(_WKProcessTerminationReason.requestedByClient) == .requestedByBrowser)
        #expect(RendererTerminationReason(_WKProcessTerminationReason.exceededSharedProcessCrashLimit) == .sharedProcessCrashed)
    }

    @Test("WebKit navigation errors map to failure kinds")
    func webKitFailures() {
        let url = URL(string: "https://nope.test/")!
        func kind(_ domain: String, _ code: Int) -> NavigationFailure.Kind? {
            guard case let .navigationFailed(failure) = PageEvent.webKitNavigationFailed(
                NSError(domain: domain, code: code), url: url, isProvisional: true,
            ) else { return nil }
            return failure.kind
        }
        #expect(kind(NSURLErrorDomain, NSURLErrorCannotFindHost) == .cannotFindHost)
        #expect(kind(NSURLErrorDomain, NSURLErrorCancelled) == .cancelled)
        #expect(kind(NSURLErrorDomain, NSURLErrorServerCertificateUntrusted) == .certificateInvalid)
        #expect(kind("WebKitErrorDomain", 102) == .cancelled)
    }

    @Test("A commit revives a terminated renderer")
    func commitRevives() {
        var state = PageSnapshot(rendererHealth: .terminated(reason: .crashed))
        PageReducer.reduce(&state, .navigationCommitted(url: URL(string: "https://a.test/")!, isBackForward: false))
        #expect(state.rendererHealth == .running)
    }
}

// MARK: - Registry

@Suite("EngineRegistry", .tags(.engines))
@MainActor
struct EngineRegistryTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = root.appending(path: "Engines/test.engine.example/Example.engine/Contents")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "test.engine.example",
            "NSPrincipalClass": "ExampleEngineHost",
            "RFXEngineContractVersion": "1.0",
            "RFXEngineDisplayName": "Example",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Info.plist"))
        return root
    }

    @Test("Discovers installed bundles after system WebKit and resolves names")
    func discovery() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.trashItem(at: root, resultingItemURL: nil) }
        let registry = EngineRegistry(applicationSupport: root)
        #expect(registry.descriptors.map(\.id) == [.systemWebKit, EngineID(rawValue: "test.engine.example")])
        #expect(registry.resolve("example") == EngineID(rawValue: "test.engine.example"))
        #expect(registry.resolve("WEBKIT") == .systemWebKit)
        #expect(registry.resolve("gecko") == nil)
    }

    @Test("An engine's icon comes from its bundle's CFBundleIconFile")
    func icon() throws {
        let id = EngineID(rawValue: "test.engine.example")
        let plain = try makeRoot()
        defer { try? FileManager.default.trashItem(at: plain, resultingItemURL: nil) }
        #expect(EngineRegistry(applicationSupport: plain).icon(for: id) == nil)

        // A second bundle: Foundation caches a Bundle's Info.plist per path.
        let iconic = try makeRoot()
        defer { try? FileManager.default.trashItem(at: iconic, resultingItemURL: nil) }
        let contents = iconic.appending(path: "Engines/test.engine.example/Example.engine/Contents")
        let infoURL = contents.appending(path: "Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any] ?? [:]
        info["CFBundleIconFile"] = "engine"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        let resources = contents.appending(path: "Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let pixel = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        try pixel.write(to: resources.appending(path: "engine.png"))

        let registry = EngineRegistry(applicationSupport: iconic)
        #expect(registry.icon(for: id) != nil)
        #expect(registry.icon(for: .systemWebKit) == nil)
    }

    @Test("A page starts in the engine its tab was moved to, else the default")
    func startingEngine() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.trashItem(at: root, resultingItemURL: nil) }
        let registry = EngineRegistry(applicationSupport: root)
        let example = EngineID(rawValue: "test.engine.example")
        let missing = EngineID(rawValue: "test.engine.missing")
        #expect(WebPagePool.startingEngine(pinned: nil, default: .systemWebKit, registry: registry) == .systemWebKit)
        #expect(WebPagePool.startingEngine(pinned: nil, default: example, registry: registry) == example)
        #expect(WebPagePool.startingEngine(pinned: EngineID.systemWebKit.rawValue, default: example, registry: registry) == .systemWebKit)
        #expect(WebPagePool.startingEngine(pinned: example.rawValue, default: .systemWebKit, registry: registry) == example)
        #expect(WebPagePool.startingEngine(pinned: nil, default: missing, registry: registry) == .systemWebKit)
        #expect(WebPagePool.startingEngine(pinned: missing.rawValue, default: example, registry: registry) == .systemWebKit)
    }

    @Test("The default engine setting stores WebKit as empty")
    func defaultEngineSetting() {
        let settings = BrowserSettings()
        #expect(settings.defaultEngineID == .systemWebKit)
        settings.defaultEngineID = EngineID(rawValue: "test.engine.example")
        #expect(settings.defaultEngineIDRaw == "test.engine.example")
        settings.defaultEngineID = .systemWebKit
        #expect(settings.defaultEngineIDRaw.isEmpty)
    }

    @Test("Uninstalling removes the engine; system WebKit can't be removed")
    func uninstall() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.trashItem(at: root, resultingItemURL: nil) }
        let registry = EngineRegistry(applicationSupport: root)
        try registry.uninstall(EngineID(rawValue: "test.engine.example"), removingData: true)
        #expect(registry.descriptors.map(\.id) == [.systemWebKit])
        #expect(throws: EngineError.self) { try registry.uninstall(.systemWebKit, removingData: false) }
    }
}

// MARK: - Scripts and channels

@Suite("Engine scripts and channels", .tags(.engines))
@MainActor
struct EngineScriptTests {
    @Test("The registry exports scripts in injection order with their worlds")
    func exportsScripts() {
        let registry = ScriptRegistry()
        let isolated = WKContentWorld.world(name: "RefraxScripts")
        registry.register(
            WKUserScript(source: "late()", injectionTime: .atDocumentEnd, forMainFrameOnly: true),
            source: .system(name: "late"), priority: 50,
        )
        registry.register(
            WKUserScript(source: "early()", injectionTime: .atDocumentStart, forMainFrameOnly: false, in: isolated),
            source: .system(name: "early"), priority: 10, world: isolated,
        )
        let scripts = registry.injectedScripts
        #expect(scripts.map(\.source) == ["early()", "late()"])
        #expect(scripts[0].world == .isolated(name: "RefraxScripts"))
        #expect(scripts[0].injectionTime == .documentStart)
        #expect(!scripts[0].mainFrameOnly)
        #expect(scripts[1].world == .page)
        #expect(scripts[1].mainFrameOnly)
    }

    @Test("Applying scripts announces them to engines")
    func announcesOnApply() {
        let registry = ScriptRegistry()
        var announced: [InjectedScript]?
        registry.onApply = { announced = $0 }
        registry.register(WKUserScript(source: "x()", injectionTime: .atDocumentEnd, forMainFrameOnly: true), source: .system(name: "x"))
        registry.apply(to: WKUserContentController())
        #expect(announced?.map(\.source) == ["x()"])
    }

    @Test("The router grants channels per world and delivers to the right handler")
    func routes() {
        let router = ScriptChannelRouter(userContentController: WKUserContentController())
        var received: [String] = []
        router.register("pageChannel") { message, _ in received.append("page:\(message.body["n"]?.stringValue ?? "")") }
        router.register("isolatedChannel", world: .isolated(name: "RefraxScripts")) { _, _ in received.append("isolated") }

        #expect(router.channelNames(in: .page) == ["pageChannel"])
        #expect(router.channelNames(in: .isolated(name: "RefraxScripts")) == ["isolatedChannel"])

        router.dispatch(ScriptMessage(channel: "pageChannel", world: .page, body: .object(["n": .string("1")]), frameURL: nil, isMainFrame: true), from: nil)
        router.dispatch(ScriptMessage(channel: "unknown", world: .page, body: .null, frameURL: nil, isMainFrame: true), from: nil)
        router.unregister("isolatedChannel", world: .isolated(name: "RefraxScripts"))
        router.dispatch(ScriptMessage(channel: "isolatedChannel", world: .isolated(name: "RefraxScripts"), body: .null, frameURL: nil, isMainFrame: true), from: nil)
        #expect(received == ["page:1"])
    }

    @Test("A channel name opened in two worlds reaches the handler of the posting world")
    func routesByWorld() {
        let router = ScriptChannelRouter(userContentController: WKUserContentController())
        let worldA = ScriptRequest.World.isolated(name: "userscript.a")
        let worldB = ScriptRequest.World.isolated(name: "userscript.b")
        var received: [String] = []
        router.register("userscript", world: worldA) { _, _ in received.append("a") }
        router.register("userscript", world: worldB) { _, _ in received.append("b") }

        router.dispatch(ScriptMessage(channel: "userscript", world: worldB, body: .null, frameURL: nil, isMainFrame: true), from: nil)
        router.dispatch(ScriptMessage(channel: "userscript", world: .page, body: .null, frameURL: nil, isMainFrame: true), from: nil)
        router.unregister("userscript", world: worldB)
        router.dispatch(ScriptMessage(channel: "userscript", world: worldB, body: .null, frameURL: nil, isMainFrame: true), from: nil)
        router.dispatch(ScriptMessage(channel: "userscript", world: worldA, body: .null, frameURL: nil, isMainFrame: true), from: nil)

        #expect(received == ["b", "a"])
        #expect(router.channelNames(in: worldA) == ["userscript"])
        #expect(router.channelNames(in: worldB).isEmpty)
    }

    @Test("Every dispatch settles the script's promise exactly once")
    func replies() async {
        struct Failure: LocalizedError {
            var errorDescription: String? { "nope" }
        }
        let router = ScriptChannelRouter(userContentController: WKUserContentController())
        router.register("oneWay") { _, _ in }
        router.register("answers", replyingWith: { message, _ in .number((message.body["n"].flatMap { if case let .number(n) = $0 { n } else { nil } } ?? 0) * 2) })
        router.register("fails", replyingWith: { _, _ in throw Failure() })

        let replies = Mutex<[String: [ScriptReply]]>([:])
        func send(_ channel: String, _ body: ScriptValue = .null) {
            router.dispatch(ScriptMessage(channel: channel, world: .page, body: body, frameURL: nil, isMainFrame: true), from: nil) { reply in
                replies.withLock { $0[channel, default: []].append(reply) }
            }
        }
        send("oneWay")
        send("answers", .object(["n": .number(21)]))
        send("fails")
        send("unknown")
        await Task.yield()

        replies.withLock { replies in
            #expect(replies["oneWay"] == [.value(value: .null)])
            #expect(replies["answers"] == [.value(value: .number(42))])
            #expect(replies["fails"] == [.error(message: "nope")])
            #expect(replies["unknown"] == [.error(message: "Unknown channel")])
        }
    }

    @Test("Download events and requests are validated like every other message")
    func downloadWire() throws {
        let progressed = try EngineWire.decodeEvent(Data(#"{"downloadProgressed":{"id":"7","receivedBytes":-5,"totalBytes":-1}}"#.utf8))
        #expect(progressed == .downloadProgressed(id: "7", receivedBytes: 0, totalBytes: 0))

        let request = try EngineWire.decodeRequest(Data(#"{"download":{"id":"7","url":"https://a.example/f.zip","suggestedFilename":"f.zip","totalBytes":42}}"#.utf8))
        #expect(request == .download(id: "7", url: URL(string: "https://a.example/f.zip")!, suggestedFilename: "f.zip", mimeType: nil, totalBytes: 42))

        #expect(throws: (any Error).self) {
            try EngineWire.decodeRequest(Data(#"{"download":{"id":"7","url":"javascript:alert(1)","suggestedFilename":"f"}}"#.utf8))
        }
    }

    @Test("Replies use the contract's labeled-case wire form")
    func replyWire() throws {
        let value = try String(decoding: EngineWire.encode(ScriptReply.value(value: .object(["a": .bool(true)]))), as: UTF8.self)
        #expect(value == #"{"value":{"value":{"a":true}}}"#)
        let error = try String(decoding: EngineWire.encode(ScriptReply.error(message: "x")), as: UTF8.self)
        #expect(error == #"{"error":{"message":"x"}}"#)
    }

    @Test("Foundation numbers bridge to Int for handlers written against WebKit messages")
    func foundationNumbers() {
        let body = ScriptValue.object(["index": .number(3), "ratio": .number(0.5)]).foundationValue as? [String: Any]
        #expect(body?["index"] as? Int == 3)
        #expect(body?["ratio"] as? Int == nil)
        #expect(body?["ratio"] as? Double == 0.5)
    }

    @Test("Reader mode messages parse from script values", arguments: [
        (ScriptValue.object(["type": .string("availability"), "url": .string("https://a.example"), "available": .bool(true)]), "availability:true"),
        (.object(["type": .string("error"), "url": .string("https://a.example")]), "error:Unknown error"),
        (.object(["type": .string("availability")]), "nil"),
        (.object(["type": .string("other"), "url": .string("https://a.example")]), "nil"),
    ])
    func readerMessages(body: ScriptValue, expected: String) {
        let description = switch ReaderModeEvent(body) {
        case let .availability(_, available): "availability:\(available)"
        case let .error(_, message): "error:\(message)"
        case .extracted: "extracted"
        case nil: "nil"
        }
        #expect(description == expected)
    }
}
