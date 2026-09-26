// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import AppKit

/// One engine instance, driven through RFXEngine.h as Refrax drives it.
@MainActor
final class TestEngine: NSObject, RFXEngineHostDelegate {
    let host: any RFXEngineHost
    let capabilities: Set<String>
    private(set) var terminationReason: String?
    private(set) var pages: [TestPage] = []
    /// Events the engine reported outside any page, in order.
    private(set) var events: [TestPage.Message] = []

    /// A new instance of the bundle's principal class. The bundle's code loads once per process;
    /// later instances reuse it, as Refrax does after an engine dies.
    init(bundle: Bundle) throws {
        if !bundle.isLoaded {
            try bundle.loadAndReturnError()
        }
        guard let principal = bundle.principalClass as? (NSObject & RFXEngineHost).Type else {
            throw Failure("the principal class does not conform to RFXEngineHost")
        }
        host = principal.init()
        capabilities = Set(bundle.object(forInfoDictionaryKey: RFXEngineInfoKey.capabilities.rawValue) as? [String] ?? [])
        super.init()
        host.delegate = self
    }

    func start(storage: URL) async throws {
        let configuration: [String: Any] = [
            "storageDirectory": storage.absoluteString,
            "logFile": storage.appending(path: "engine.log").absoluteString,
            "languages": ["en-US"],
        ]
        let data = JSON.data(configuration)
        try await callback("engine start", timeout: 60) { (done: @escaping @MainActor (Result<Void, Error>) -> Void) in
            host.start(withConfiguration: data) { error in
                MainActor.assumeIsolated { done(error.map { .failure($0) } ?? .success(())) }
            }
        }
    }

    /// Starts the engine from inside a nested run loop, as Refrax does when a menu action opens
    /// the first page of an engine: an engine must not assume which loop its start runs in.
    func startFromNestedLoop(storage: URL) async throws {
        let configuration: [String: Any] = [
            "storageDirectory": storage.absoluteString,
            "logFile": storage.appending(path: "engine.log").absoluteString,
            "languages": ["en-US"],
        ]
        let data = JSON.data(configuration)
        let outcome = StartOutcome()
        let trackingMode = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)
        CFRunLoopPerformBlock(CFRunLoopGetMain(), trackingMode.rawValue) {
            MainActor.assumeIsolated {
                self.host.start(withConfiguration: data) { error in
                    MainActor.assumeIsolated { outcome.result = error.map { .failure($0) } ?? .success(()) }
                }
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        spinNestedLoop(trackingMode, seconds: 0.5)
        try await eventually("engine start", timeout: 60) { outcome.result }.get()
    }

    func apply(_ update: [String: Any]) {
        host.applyPolicy(JSON.data(update))
    }

    /// Sends an EngineCommand, which engines implement optionally.
    func command(_ name: String, _ fields: [String: Any] = [:]) throws {
        guard host.responds(to: #selector(RFXEngineHost.performCommand(_:))) else {
            throw Failure("the engine takes no engine commands (performCommand:)")
        }
        host.performCommand?(JSON.data([name: fields]))
    }

    /// The first engine event named `name` that satisfies `matching`.
    @discardableResult
    func waitForEvent(_ name: String, timeout: TimeInterval = 10, matching: ([String: Any]) -> Bool = { _ in true }) async throws -> [String: Any] {
        try await eventually("engine event \(name)", timeout: timeout) {
            events.first { $0.name == name && matching($0.fields) }?.fields
        }
    }

    func require(_ capability: String) throws {
        if !capabilities.contains(capability) {
            throw Skip("engine does not declare \(capability)")
        }
    }

    /// A page in a window of its own, loading `url`.
    func makePage(_ url: String, profile: [String: Any] = ["shared": [:]], size: NSSize = NSSize(width: 1000, height: 700)) throws -> TestPage {
        let spec: [String: Any] = ["id": UUID().uuidString, "profile": profile, "initialURL": url]
        let page = try host.makePage(withSpec: JSON.data(spec))
        let testPage = TestPage(page: page, size: size)
        pages.append(testPage)
        return testPage
    }

    func removeProfile(_ profile: [String: Any]) async throws {
        try await callback("removeProfile", timeout: 180) { (done: @escaping @MainActor (Result<Void, Error>) -> Void) in
            host.removeProfile(JSON.data(profile)) {
                MainActor.assumeIsolated { done(.success(())) }
            }
        }
    }

    /// Closes every page a test left open.
    func closeAll() {
        for page in pages where !page.isClosed {
            page.close()
        }
        pages.removeAll()
    }

    func engineHostDidTerminate(withReason reason: String) {
        terminationReason = reason
    }

    func engineHost(_ host: any RFXEngineHost, didEmitEvent event: Data) {
        if let message = JSON.message(event) {
            events.append(TestPage.Message(name: message.name, fields: message.fields))
        }
    }
}

/// Runs a nested loop in `mode`, as AppKit does while a menu tracks.
private func spinNestedLoop(_ mode: CFRunLoopMode, seconds: Double) {
    _ = CFRunLoopRunInMode(mode, seconds, false)
}

@MainActor
private final class StartOutcome {
    var result: Result<Void, Error>?
}

/// One page: records everything the engine reports and answers its questions.
@MainActor
final class TestPage: NSObject, RFXEnginePageDelegate {
    struct Message {
        let name: String
        let fields: [String: Any]
    }

    let page: any RFXEnginePage
    let window: NSWindow
    private(set) var events: [Message] = []
    private(set) var requests: [Message] = []
    private(set) var scriptMessages: [[String: Any]] = []
    private(set) var isClosed = false
    /// Callbacks that arrived after `close()`; the contract allows none.
    private(set) var callbacksAfterClose = 0

    /// Answers each request; returns nil to leave it unanswered (the reply is kept in
    /// `pendingReplies`). Defaults to a user who confirms dialogs, denies permissions, lets
    /// Refrax open URLs and cancels downloads.
    var answer: (Message) -> [String: Any]? = TestPage.defaultAnswer
    private(set) var pendingReplies: [(Data) -> Void] = []
    /// Answers each script message; defaults to resolving with the message's body.
    var reply: ([String: Any]) -> [String: Any] = { message in
        ["value": ["value": message["body"] ?? NSNull()]]
    }

    init(page: any RFXEnginePage, size: NSSize) {
        self.page = page
        window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.title = "engine-conformance"
        super.init()
        page.delegate = self
        let view = page.view
        view.frame = window.contentView!.bounds
        view.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(view)
        window.orderFrontRegardless()
    }

    nonisolated static func defaultAnswer(_ request: Message) -> [String: Any]? {
        switch request.name {
        case "openURL": ["handled": [:]]
        case "permission": ["deny": [:]]
        case "javaScriptDialog": ["confirm": ["text": "conformance"]]
        default: ["cancel": [:]]
        }
    }

    // MARK: Commands

    func command(_ name: String, _ fields: [String: Any] = [:]) {
        page.performCommand(JSON.data([name: fields]))
    }

    /// Loads `url` and waits for it to finish.
    @discardableResult
    func load(_ url: String, headers: [String: String] = [:], timeout: TimeInterval = 20) async throws -> [String: Any] {
        let mark = events.count
        command("load", ["request": ["url": url, "headers": headers]])
        return try await waitForFinish(after: mark, timeout: timeout)
    }

    /// Waits for the next `navigationFinished` after event index `mark`, failing early on a
    /// `navigationFailed`.
    @discardableResult
    func waitForFinish(after mark: Int = 0, timeout: TimeInterval = 20) async throws -> [String: Any] {
        try await eventually("navigationFinished", timeout: timeout) {
            for event in events[mark...] {
                if event.name == "navigationFinished" { return event.fields }
                if event.name == "navigationFailed" {
                    throw Failure("navigation failed: \(JSON.canonical(event.fields))")
                }
            }
            return nil
        }
    }

    /// The first event named `name` after index `mark` that satisfies `matching`.
    @discardableResult
    func waitForEvent(_ name: String, after mark: Int = 0, timeout: TimeInterval = 10, matching: ([String: Any]) -> Bool = { _ in true }) async throws -> [String: Any] {
        try await eventually("event \(name)", timeout: timeout) {
            events[mark...].first { $0.name == name && matching($0.fields) }?.fields
        }
    }

    @discardableResult
    func waitForRequest(_ name: String, after mark: Int = 0, timeout: TimeInterval = 10) async throws -> [String: Any] {
        try await eventually("request \(name)", timeout: timeout) {
            requests[mark...].first { $0.name == name }?.fields
        }
    }

    /// The raw JSON result of evaluating `source`.
    func evaluateRaw(_ source: String, world: String? = nil, gesture: Bool = false, timeout: TimeInterval = 15) async throws -> Data {
        let request: [String: Any] = [
            "source": source,
            "world": world.map { ["isolated": ["name": $0]] } ?? ["page": [:]],
            "userGesture": gesture,
        ]
        let data = JSON.data(request)
        return try await callback("evaluate \(source.prefix(60))", timeout: timeout) { (done: @escaping @MainActor (Result<Data, Error>) -> Void) in
            page.evaluateScript(data) { result, error in
                MainActor.assumeIsolated {
                    if let result {
                        done(.success(result))
                    } else {
                        done(.failure(EvaluationError(message: error?.localizedDescription ?? "no result and no error")))
                    }
                }
            }
        }
    }

    /// The parsed result of evaluating `source`; JSON null comes back as NSNull.
    func evaluate(_ source: String, world: String? = nil, gesture: Bool = false, timeout: TimeInterval = 15) async throws -> Any {
        let data = try await evaluateRaw(source, world: world, gesture: gesture, timeout: timeout)
        guard let value = JSON.parse(data) else {
            throw Failure("evaluation returned invalid JSON: \(String(decoding: data, as: UTF8.self))")
        }
        return value
    }

    /// The message of the error evaluating `source` produces; fails if it succeeds.
    func evaluationError(_ source: String, world: String? = nil) async throws -> String {
        do {
            let data = try await evaluateRaw(source, world: world)
            throw Failure("expected an error, got \(String(decoding: data, as: UTF8.self))")
        } catch let error as EvaluationError {
            return error.message
        }
    }

    func snapshot(_ rect: NSRect = .zero) async throws -> CGImage {
        try await callback("snapshot", timeout: 15) { (done: @escaping @MainActor (Result<CGImage, Error>) -> Void) in
            page.snapshotRect(rect) { image, error in
                MainActor.assumeIsolated {
                    if let image {
                        done(.success(image))
                    } else {
                        done(.failure(Failure("snapshot failed: \(error?.localizedDescription ?? "no error")")))
                    }
                }
            }
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        page.close()
        window.orderOut(nil)
    }

    // MARK: RFXEnginePageDelegate

    func enginePage(_ page: any RFXEnginePage, didEmitEvent event: Data) {
        guard !isClosed else { callbacksAfterClose += 1; return }
        if let message = JSON.message(event) {
            events.append(Message(name: message.name, fields: message.fields))
        }
    }

    func enginePage(_ page: any RFXEnginePage, didRequest request: Data, reply: @escaping (Data) -> Void) {
        guard !isClosed else { callbacksAfterClose += 1; return }
        guard let message = JSON.message(request) else {
            reply(JSON.data(["cancel": [:]]))
            return
        }
        let request = Message(name: message.name, fields: message.fields)
        requests.append(request)
        if let answer = answer(request) {
            reply(JSON.data(answer))
        } else {
            pendingReplies.append(reply)
        }
    }

    func enginePage(_ page: any RFXEnginePage, didReceiveScriptMessage message: Data, reply: @escaping (Data) -> Void) {
        guard !isClosed else { callbacksAfterClose += 1; return }
        let parsed = JSON.parse(message) as? [String: Any] ?? [:]
        scriptMessages.append(parsed)
        reply(JSON.data(self.reply(parsed)))
    }
}

struct EvaluationError: Error {
    let message: String
}
