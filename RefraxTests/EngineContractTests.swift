import Foundation
@testable import Refrax
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
