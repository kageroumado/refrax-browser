import AppKit

// MARK: - Host

/// Drives an engine bundle through the `RFXEngine.h` binary interface.
///
/// Everything the bundle sends is decoded and validated by ``EngineWire``;
/// nothing from the engine reaches Refrax as a live object except its view.
@MainActor
final class ExternalEngineHost: NSObject, EngineHost {
    let bundle: EngineBundle
    let events: AsyncStream<HostEvent>

    private let eventContinuation: AsyncStream<HostEvent>.Continuation
    private let configuration: EngineConfiguration
    private var runtime: (any RFXEngineHost)?
    private var startTask: Task<Void, any Error>?
    private var pages: [EnginePageID: WeakPage] = [:]

    private struct WeakPage {
        weak var page: ExternalEnginePage?
    }

    var descriptor: EngineDescriptor {
        bundle.descriptor
    }

    init(bundle: EngineBundle, configuration: EngineConfiguration) {
        self.bundle = bundle
        self.configuration = configuration
        (events, eventContinuation) = AsyncStream.makeStream()
        super.init()
    }

    func start() async throws {
        if let startTask {
            return try await startTask.value
        }
        let task = Task { try await load() }
        startTask = task
        do {
            try await task.value
        } catch {
            startTask = nil
            throw error
        }
    }

    private func load() async throws {
        let id = descriptor.id
        guard EngineContractVersion.current.accepts(descriptor.contractVersion) else {
            throw EngineError.incompatibleContract(id, engine: descriptor.contractVersion)
        }
        try bundle.verifySignature()

        guard let nsBundle = Bundle(url: bundle.url) else {
            throw EngineError.failedToLoad(id, reason: "The bundle could not be opened.")
        }
        do {
            try nsBundle.loadAndReturnError()
        } catch {
            throw EngineError.failedToLoad(id, reason: error.localizedDescription)
        }
        guard let hostClass = NSClassFromString(bundle.principalClassName) as? NSObject.Type,
              let runtime = hostClass.init() as? any RFXEngineHost else {
            throw EngineError.failedToLoad(id, reason: "\(bundle.principalClassName) does not conform to RFXEngineHost.")
        }
        runtime.delegate = self

        try FileManager.default.createDirectory(at: configuration.storageDirectory, withIntermediateDirectories: true)
        let configurationData = try EngineWire.encode(configuration)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            runtime.start(withConfiguration: configurationData) { error in
                if let error {
                    continuation.resume(throwing: EngineError.failedToStart(id, reason: error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
        self.runtime = runtime
        Logger.info("Engine \(id) started (\(descriptor.engineVersion))", category: Logger.engines)
    }

    func makePage(_ spec: EnginePageSpec) throws -> any EnginePage {
        guard let runtime else { throw EngineError.failedToStart(descriptor.id, reason: "The engine is not running.") }
        let page = try runtime.makePage(withSpec: EngineWire.encode(spec))
        let adapter = ExternalEnginePage(id: spec.id, engine: descriptor, runtimePage: page)
        pages[spec.id] = WeakPage(page: adapter)
        return adapter
    }

    func apply(_ update: PolicyUpdate) {
        guard let runtime, let data = try? EngineWire.encode(update) else { return }
        runtime.applyPolicy(data)
    }

    func removeProfile(_ profile: EngineProfileSpec) async {
        guard let runtime, let data = try? EngineWire.encode(profile) else { return }
        await withCheckedContinuation { continuation in
            runtime.removeProfile(data) { continuation.resume() }
        }
    }

    func processInfo() async -> [EngineProcessInfo] {
        []
    }

    func shutdown() {
        runtime?.shutdown()
        runtime = nil
        startTask = nil
        eventContinuation.finish()
    }
}

extension ExternalEngineHost: RFXEngineHostDelegate {
    func engineHostDidTerminate(withReason reason: String) {
        Logger.warning("Engine \(descriptor.id) terminated: \(reason)", category: Logger.engines)
        for entry in pages.values {
            entry.page?.hostDidTerminate()
        }
        runtime = nil
        startTask = nil
        eventContinuation.yield(.terminated(reason: reason))
    }
}

// MARK: - Page

@MainActor
final class ExternalEnginePage: NSObject, EnginePage {
    /// Rejected messages tolerated before the page stops listening to its engine.
    private static let malformedMessageLimit = 32

    let id: EnginePageID
    let engine: EngineDescriptor
    let events: AsyncStream<PageEvent>
    let requests: AsyncStream<PageRequest>
    let messages: AsyncStream<ScriptMessage>

    private let eventContinuation: AsyncStream<PageEvent>.Continuation
    private let requestContinuation: AsyncStream<PageRequest>.Continuation
    private let messageContinuation: AsyncStream<ScriptMessage>.Continuation
    private var runtimePage: (any RFXEnginePage)?
    private var malformedMessages = 0

    init(id: EnginePageID, engine: EngineDescriptor, runtimePage: any RFXEnginePage) {
        self.id = id
        self.engine = engine
        self.runtimePage = runtimePage
        (events, eventContinuation) = AsyncStream.makeStream()
        (requests, requestContinuation) = AsyncStream.makeStream()
        (messages, messageContinuation) = AsyncStream.makeStream()
        super.init()
        runtimePage.delegate = self
    }

    var view: NSView {
        runtimePage?.view ?? NSView()
    }

    func perform(_ command: PageCommand) {
        guard let runtimePage, let data = try? EngineWire.encode(command) else { return }
        runtimePage.performCommand(data)
    }

    func evaluate(_ request: ScriptRequest) async throws -> ScriptValue {
        guard let runtimePage else { throw EngineError.pageClosed }
        let data = try EngineWire.encode(request)
        let result: Data = try await withCheckedThrowingContinuation { continuation in
            runtimePage.evaluateScript(data) { result, error in
                if let error {
                    continuation.resume(throwing: EngineError.scriptFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: result ?? Data("null".utf8))
                }
            }
        }
        return try EngineWire.decode(ScriptValue.self, from: result)
    }

    func snapshot(of rect: CGRect?) async throws -> CGImage {
        guard let runtimePage else { throw EngineError.pageClosed }
        let image: CGImage = try await withCheckedThrowingContinuation { continuation in
            runtimePage.snapshotRect(rect ?? .zero) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? EngineError.unsupported(.snapshots))
                }
            }
        }
        return image
    }

    func close() {
        runtimePage?.delegate = nil
        runtimePage?.close()
        runtimePage = nil
        finishStreams()
    }

    fileprivate func hostDidTerminate() {
        eventContinuation.yield(.rendererHealthChanged(health: .terminated(reason: .crashed)))
        runtimePage = nil
        finishStreams()
    }

    private func finishStreams() {
        eventContinuation.finish()
        requestContinuation.finish()
        messageContinuation.finish()
    }

    private func reject(_ error: any Error) {
        malformedMessages += 1
        Logger.warning("Engine \(engine.id) sent a rejected message: \(error.localizedDescription)", category: Logger.engines)
        if malformedMessages == Self.malformedMessageLimit {
            Logger.error("Engine \(engine.id) exceeded the malformed-message limit; closing page \(id.rawValue)", category: Logger.engines)
            close()
        }
    }
}

extension ExternalEnginePage: RFXEnginePageDelegate {
    func enginePage(_: any RFXEnginePage, didEmitEvent event: Data) {
        do {
            try eventContinuation.yield(EngineWire.decodeEvent(event))
        } catch {
            reject(error)
        }
    }

    func enginePage(_: any RFXEnginePage, didRequest request: Data, reply: @escaping (Data) -> Void) {
        let kind: PageRequestKind
        do {
            kind = try EngineWire.decodeRequest(request)
        } catch {
            reject(error)
            reply((try? EngineWire.encode(PageRequestAnswer.cancel)) ?? Data())
            return
        }
        let once = ReplyOnce(reply)
        requestContinuation.yield(PageRequest(kind: kind) { answer in
            once.send((try? EngineWire.encode(answer)) ?? Data())
        })
    }

    func enginePage(_: any RFXEnginePage, didReceiveScriptMessage message: Data) {
        do {
            try messageContinuation.yield(EngineWire.decode(ScriptMessage.self, from: message))
        } catch {
            reject(error)
        }
    }
}

/// Guarantees an engine's reply block runs exactly once, on the main thread.
private nonisolated final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: ((Data) -> Void)?

    init(_ reply: @escaping (Data) -> Void) {
        self.reply = reply
    }

    func send(_ data: Data) {
        lock.lock()
        let reply = reply
        self.reply = nil
        lock.unlock()
        guard let reply else { return }
        DispatchQueue.main.async { reply(data) }
    }
}
