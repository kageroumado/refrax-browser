import Darwin
import Foundation
import os

/// In-process HTTP server that impersonates an OpenAI-compatible Chat
/// Completions endpoint for end-to-end integration tests.
///
/// The server binds to `127.0.0.1` on an ephemeral port so multiple tests
/// can run in parallel without port collisions. Tests schedule scripted
/// responses ahead of time; each incoming request consumes one scripted
/// response in FIFO order. Raw request metadata (method/path/headers/body)
/// is captured so assertions can verify wire-level correctness.
///
/// ## Lifecycle
///
/// ```swift
/// let server = try await MockOpenAIServer.start()
/// defer { Task { await server.stop() } }
/// await server.scheduleResponse(.streamText(["Hello ", "world"]))
/// // …point the client at server.baseURL and exercise it…
/// ```
///
/// The server closes its listening socket on ``stop()`` (and in ``deinit``)
/// to prevent port leaks across tests.
///
/// ## Why POSIX sockets rather than Network.framework
///
/// `NWListener` fails with `POSIXErrorCode 22 (EINVAL)` on this macOS test
/// environment regardless of parameters (bound port, protocol stack, or
/// endpoint shape). Plain BSD sockets bind + listen + accept reliably and
/// are fully supported by the Refrax host app's entitlements.
///
/// ## Concurrency model
///
/// State is guarded by an internal `OSAllocatedUnfairLock` rather than an
/// actor. Each accepted connection runs synchronously on a dedicated GCD
/// thread from a concurrent queue, using blocking `recv` / `send`. An
/// actor-based design was tried but deadlocks under Swift concurrency's
/// cooperative thread pool: blocking socket reads starve tasks that would
/// otherwise make progress (client-side ``URLSession/bytes(for:)``
/// consumers, test continuations). A lock-and-dispatch model is simpler
/// and robust — `OSAllocatedUnfairLock` is Swift 6 strict-concurrency safe
/// because its `withLock` API cannot be called across a suspension point.
final class MockOpenAIServer: @unchecked Sendable {
    // MARK: - Scripted Responses

    /// A server response the test schedules before the client connects.
    enum ScriptedResponse: Sendable {
        /// Streams text deltas as `choices[0].delta.content` SSE frames, then
        /// a `finish_reason: "stop"` frame, then `[DONE]`.
        case streamText([String])

        /// Streams text deltas followed by a final chunk containing `choices:[]`
        /// plus a `usage` object, then `[DONE]`.
        case streamTextWithUsage([String], usage: UsageStub)

        /// Streams a single tool call arriving as one complete arguments string,
        /// then `finish_reason: "tool_calls"`, then `[DONE]`.
        case streamToolCall(id: String, name: String, argumentsJSON: String)

        /// Streams a single tool call whose `arguments` payload is emitted as
        /// multiple fragments (to validate accumulation-by-index).
        case streamToolCallFragmented(id: String, name: String, argumentFragments: [String])

        /// Replies with the given HTTP status, body, and headers. No streaming.
        case error(status: Int, body: String, headers: [String: String] = [:])

        /// Test-controlled streaming — the test drives chunk emission through
        /// the supplied ``StreamController``. Used by the abort test.
        case controllable(StreamController)
    }

    /// Stubbed usage payload for ``ScriptedResponse/streamTextWithUsage``.
    struct UsageStub: Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
        }
    }

    /// A response for `GET /v1/models` requests.
    struct ModelsListResponse: Sendable {
        let entries: [(id: String, name: String?)]

        init(_ entries: [(id: String, name: String?)]) {
            self.entries = entries
        }
    }

    // MARK: - Recorded Requests

    /// A captured incoming HTTP request.
    struct RecordedRequest: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        /// Attempt to parse the body as JSON for convenient assertions.
        var bodyJSON: [String: Any]? {
            guard !body.isEmpty else { return nil }
            return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }

        /// Case-insensitive header lookup — HTTP/1.1 headers are case-insensitive.
        func header(_ name: String) -> String? {
            let lower = name.lowercased()
            for (key, value) in headers where key.lowercased() == lower {
                return value
            }
            return nil
        }
    }

    // MARK: - State (guarded by `state`)

    private struct LockedState {
        var modelsResponse: ModelsListResponse = .init([])
        var scheduledResponses: [ScriptedResponse] = []
        var recordedRequests: [RecordedRequest] = []
        var requestWaiters: [CheckedContinuation<RecordedRequest, Never>] = []
        var disconnectWaiters: [CheckedContinuation<Void, Never>] = []
        var requestWaiterCursor = 0
        var isStopped = false
    }

    private let state = OSAllocatedUnfairLock<LockedState>(initialState: LockedState())

    // MARK: - Networking State

    private let listenFD: Int32
    private let acceptQueue: DispatchQueue
    private let acceptSource: DispatchSourceRead
    private let ioQueue: DispatchQueue

    /// The resolved listening port, known after bind+getsockname at construction.
    let port: UInt16

    /// Base URL suitable for passing to ``OpenAIProviderConfig``.
    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)/v1")!
    }

    // MARK: - Init

    private init(
        listenFD: Int32,
        port: UInt16,
        acceptQueue: DispatchQueue,
        acceptSource: DispatchSourceRead,
        ioQueue: DispatchQueue,
    ) {
        self.listenFD = listenFD
        self.port = port
        self.acceptQueue = acceptQueue
        self.acceptSource = acceptSource
        self.ioQueue = ioQueue
    }

    deinit {
        acceptSource.cancel()
        close(listenFD)
    }

    // MARK: - Start

    /// Starts a fresh server bound to `127.0.0.1` on an ephemeral port. The
    /// returned server is ready to accept requests when this function returns.
    static func start() throws -> MockOpenAIServer {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { throw MockServerError.socketFailed(errno) }

        // SO_REUSEADDR so repeated test runs don't hit TIME_WAIT.
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to 127.0.0.1:0 — kernel picks an unused port.
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { cast in
                Darwin.bind(fd, cast, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult < 0 {
            let err = errno
            close(fd)
            throw MockServerError.bindFailed(err)
        }

        if listen(fd, /* backlog: */ 32) < 0 {
            let err = errno
            close(fd)
            throw MockServerError.listenFailed(err)
        }

        // Read back the assigned port.
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &local) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { cast in
                getsockname(fd, cast, &len)
            }
        }
        if nameResult < 0 {
            let err = errno
            close(fd)
            throw MockServerError.getsocknameFailed(err)
        }
        let port = UInt16(bigEndian: local.sin_port)

        // Non-blocking accept so the DispatchSource can loop.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        let acceptQueue = DispatchQueue(label: "MockOpenAIServer.accept", qos: .userInitiated)
        let ioQueue = DispatchQueue(label: "MockOpenAIServer.io", qos: .userInitiated, attributes: .concurrent)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)

        let server = MockOpenAIServer(
            listenFD: fd,
            port: port,
            acceptQueue: acceptQueue,
            acceptSource: source,
            ioQueue: ioQueue,
        )

        source.setEventHandler { [weak server] in
            guard let server else { return }
            // Drain all pending connections before returning — otherwise
            // dispatch may coalesce events and leave backlog stalled.
            while true {
                var clientAddr = sockaddr()
                var clientLen = socklen_t(MemoryLayout<sockaddr>.size)
                let clientFD = accept(fd, &clientAddr, &clientLen)
                if clientFD < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { return }
                    return
                }
                // Accepted sockets inherit O_NONBLOCK on Darwin — clear it so
                // `recv` on the I/O queue blocks until data arrives.
                let flags = fcntl(clientFD, F_GETFL, 0)
                _ = fcntl(clientFD, F_SETFL, flags & ~O_NONBLOCK)
                server.ioQueue.async {
                    server.handleConnection(clientFD: clientFD)
                }
            }
        }
        source.activate()

        return server
    }

    // MARK: - Public API

    /// Schedules the next response for `POST /v1/chat/completions`.
    /// Responses are consumed FIFO in the order they were scheduled.
    func scheduleResponse(_ response: ScriptedResponse) {
        state.withLock { $0.scheduledResponses.append(response) }
    }

    /// Sets the payload returned from `GET /v1/models`.
    func setModelsResponse(_ response: ModelsListResponse) {
        state.withLock { $0.modelsResponse = response }
    }

    /// Snapshot of all recorded requests in arrival order.
    func receivedRequests() -> [RecordedRequest] {
        state.withLock { $0.recordedRequests }
    }

    /// Suspends until one more request arrives. If a request has already
    /// arrived and hasn't been awaited, returns it immediately.
    func waitForNextRequest() async -> RecordedRequest {
        await withCheckedContinuation { continuation in
            let immediate: RecordedRequest? = state.withLock { locked in
                if locked.recordedRequests.count > locked.requestWaiterCursor {
                    let request = locked.recordedRequests[locked.requestWaiterCursor]
                    locked.requestWaiterCursor += 1
                    return request
                } else {
                    locked.requestWaiters.append(continuation)
                    return nil
                }
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }

    /// Suspends until the next client-initiated TCP disconnect.
    func waitForDisconnect() async {
        await withCheckedContinuation { continuation in
            state.withLock { $0.disconnectWaiters.append(continuation) }
        }
    }

    /// Cancels the listener and releases any pending waiters.
    func stop() async {
        let disconnects: [CheckedContinuation<Void, Never>]? = state.withLock { locked in
            guard !locked.isStopped else { return nil }
            locked.isStopped = true
            let pending = locked.disconnectWaiters
            locked.disconnectWaiters.removeAll()
            return pending
        }
        guard let disconnects else { return }
        acceptSource.cancel()
        close(listenFD)
        for waiter in disconnects {
            waiter.resume()
        }
    }

    // MARK: - State Helpers (internal, locked)

    private func recordRequest(_ request: RecordedRequest) {
        let pending: CheckedContinuation<RecordedRequest, Never>? = state.withLock { locked in
            locked.recordedRequests.append(request)
            guard !locked.requestWaiters.isEmpty else { return nil }
            locked.requestWaiterCursor += 1
            return locked.requestWaiters.removeFirst()
        }
        pending?.resume(returning: request)
    }

    private func notifyDisconnect() {
        let waiters: [CheckedContinuation<Void, Never>] = state.withLock { locked in
            let pending = locked.disconnectWaiters
            locked.disconnectWaiters.removeAll()
            return pending
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func takeNextScriptedResponse() -> ScriptedResponse? {
        state.withLock { locked in
            guard !locked.scheduledResponses.isEmpty else { return nil }
            return locked.scheduledResponses.removeFirst()
        }
    }

    private func snapshotModelsResponse() -> ModelsListResponse {
        state.withLock { $0.modelsResponse }
    }

    // MARK: - Connection Handling (on ioQueue)

    /// Runs synchronously on the I/O queue. Handles the full request/response
    /// cycle with blocking `recv` / `send`, then closes the socket.
    private func handleConnection(clientFD: Int32) {
        let rawRequest: HTTPRequest
        do {
            rawRequest = try HTTPRequest.read(fd: clientFD)
        } catch {
            Darwin.close(clientFD)
            notifyDisconnect()
            return
        }

        let recorded = RecordedRequest(
            method: rawRequest.method,
            path: rawRequest.path,
            headers: rawRequest.headers,
            body: rawRequest.body,
        )
        recordRequest(recorded)

        if rawRequest.method == "GET", rawRequest.path == "/v1/models" {
            let models = snapshotModelsResponse()
            let payload = Self.encodeModelsResponse(models)
            Self.sendPlainResponse(fd: clientFD, status: 200, contentType: "application/json", body: payload)
            Self.shutdownAndClose(clientFD)
            return
        }

        if rawRequest.method == "POST", rawRequest.path == "/v1/chat/completions" {
            guard let scripted = takeNextScriptedResponse() else {
                Self.sendPlainResponse(
                    fd: clientFD,
                    status: 500,
                    contentType: "application/json",
                    body: Data(#"{"error":{"message":"no scripted response","type":"server_error"}}"#.utf8),
                )
                Self.shutdownAndClose(clientFD)
                return
            }
            dispatch(scripted: scripted, on: clientFD)
            return
        }

        Self.sendPlainResponse(
            fd: clientFD,
            status: 404,
            contentType: "application/json",
            body: Data(#"{"error":{"message":"not found","type":"not_found"}}"#.utf8),
        )
        Self.shutdownAndClose(clientFD)
    }

    private func dispatch(scripted: ScriptedResponse, on fd: Int32) {
        switch scripted {
        case let .streamText(deltas):
            Self.startSSE(fd: fd)
            for delta in deltas {
                Self.writeFrame(Self.makeTextDeltaFrame(content: delta), on: fd)
            }
            Self.writeFrame(Self.makeFinishFrame(reason: "stop", usage: nil), on: fd)
            Self.writeDone(on: fd)
            Self.shutdownAndClose(fd)

        case let .streamTextWithUsage(deltas, usage):
            Self.startSSE(fd: fd)
            for delta in deltas {
                Self.writeFrame(Self.makeTextDeltaFrame(content: delta), on: fd)
            }
            Self.writeFrame(Self.makeFinishFrame(reason: "stop", usage: nil), on: fd)
            Self.writeFrame(Self.makeUsageOnlyFrame(usage: usage), on: fd)
            Self.writeDone(on: fd)
            Self.shutdownAndClose(fd)

        case let .streamToolCall(id, name, argumentsJSON):
            Self.startSSE(fd: fd)
            Self.writeFrame(Self.makeToolCallOpenFrame(id: id, name: name), on: fd)
            Self.writeFrame(Self.makeToolCallArgumentsFrame(argumentsChunk: argumentsJSON), on: fd)
            Self.writeFrame(Self.makeFinishFrame(reason: "tool_calls", usage: nil), on: fd)
            Self.writeDone(on: fd)
            Self.shutdownAndClose(fd)

        case let .streamToolCallFragmented(id, name, argumentFragments):
            Self.startSSE(fd: fd)
            Self.writeFrame(Self.makeToolCallOpenFrame(id: id, name: name), on: fd)
            for chunk in argumentFragments {
                Self.writeFrame(Self.makeToolCallArgumentsFrame(argumentsChunk: chunk), on: fd)
            }
            Self.writeFrame(Self.makeFinishFrame(reason: "tool_calls", usage: nil), on: fd)
            Self.writeDone(on: fd)
            Self.shutdownAndClose(fd)

        case let .error(status, body, headers):
            Self.sendPlainResponse(
                fd: fd,
                status: status,
                contentType: headers["Content-Type"] ?? "application/json",
                body: Data(body.utf8),
                extraHeaders: headers,
            )
            Self.shutdownAndClose(fd)

        case let .controllable(controller):
            runControllableStream(controller: controller, fd: fd)
        }
    }

    /// Drives a test-controlled stream synchronously. Each chunk request
    /// blocks the I/O queue thread until the test produces a new chunk —
    /// since `StreamController` exposes a plain blocking API
    /// (`nextChunkSync()`), no actor hop is needed.
    private func runControllableStream(controller: StreamController, fd: Int32) {
        Self.startSSE(fd: fd)
        while let chunk = controller.nextChunkSync() {
            switch chunk {
            case let .frame(json):
                Self.writeRaw(Data("data: \(json)\n\n".utf8), on: fd)
            case .done:
                Self.writeDone(on: fd)
            case .close:
                break
            }
        }
        Self.shutdownAndClose(fd)
        notifyDisconnect()
    }

    // MARK: - Frame Construction (static — pure)

    static func makeTextDeltaFrame(content: String) -> String {
        let escaped = jsonEscape(content)
        return #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":0,"model":"test-model","choices":[{"index":0,"delta":{"content":"\#(escaped)"},"finish_reason":null}]}"#
    }

    static func makeFinishFrame(reason: String, usage: UsageStub?) -> String {
        var json = #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":0,"model":"test-model","choices":[{"index":0,"delta":{},"finish_reason":"\#(reason)"}]"#
        if let usage {
            json += #","usage":{"prompt_tokens":\#(usage.promptTokens),"completion_tokens":\#(usage.completionTokens),"total_tokens":\#(usage.totalTokens)}"#
        }
        json += "}"
        return json
    }

    static func makeUsageOnlyFrame(usage: UsageStub) -> String {
        #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":0,"model":"test-model","choices":[],"usage":{"prompt_tokens":\#(usage.promptTokens),"completion_tokens":\#(usage.completionTokens),"total_tokens":\#(usage.totalTokens)}}"#
    }

    static func makeToolCallOpenFrame(id: String, name: String) -> String {
        #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":0,"model":"test-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"\#(id)","type":"function","function":{"name":"\#(name)","arguments":""}}]},"finish_reason":null}]}"#
    }

    static func makeToolCallArgumentsFrame(argumentsChunk: String) -> String {
        let escaped = jsonEscape(argumentsChunk)
        return #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":0,"model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\#(escaped)"}}]},"finish_reason":null}]}"#
    }

    /// Minimal JSON string escaping (RFC 8259). Enough for the canned fixtures
    /// used by tests.
    static func jsonEscape(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for scalar in input.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    private static func encodeModelsResponse(_ response: ModelsListResponse) -> Data {
        let entries: [[String: Any]] = response.entries.map { entry in
            var dict: [String: Any] = ["id": entry.id]
            if let name = entry.name { dict["name"] = name }
            return dict
        }
        let payload: [String: Any] = ["object": "list", "data": entries]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    // MARK: - Wire Writers

    static func startSSE(fd: Int32) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        writeRaw(Data(header.utf8), on: fd)
    }

    static func writeFrame(_ json: String, on fd: Int32) {
        writeRaw(Data("data: \(json)\n\n".utf8), on: fd)
    }

    static func writeDone(on fd: Int32) {
        writeRaw(Data("data: [DONE]\n\n".utf8), on: fd)
    }

    static func sendPlainResponse(
        fd: Int32,
        status: Int,
        contentType: String,
        body: Data,
        extraHeaders: [String: String] = [:],
    ) {
        var headerLines = [
            "HTTP/1.1 \(status) \(statusPhrase(status))",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
        ]
        for (key, value) in extraHeaders where key.lowercased() != "content-type" {
            headerLines.append("\(key): \(value)")
        }
        let head = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        writeRaw(data, on: fd)
    }

    private static func statusPhrase(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        default: "Status"
        }
    }

    static func writeRaw(_ data: Data, on fd: Int32) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let n = send(fd, base.advanced(by: offset), data.count - offset, 0)
                if n <= 0 {
                    if errno == EINTR { continue }
                    return
                }
                offset += n
            }
        }
    }

    static func shutdownAndClose(_ fd: Int32) {
        // Half-close our write side so the client sees EOF.
        Darwin.shutdown(fd, SHUT_WR)
        // Drain any remaining input so the client's close doesn't RST us.
        var sink = [UInt8](repeating: 0, count: 1_024)
        while true {
            let n = sink.withUnsafeMutableBufferPointer { buf in
                recv(fd, buf.baseAddress, buf.count, 0)
            }
            if n <= 0 { break }
        }
        close(fd)
    }
}

// MARK: - Errors

enum MockServerError: Error {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case getsocknameFailed(Int32)
    case malformedRequest
    case timeout
}

// MARK: - Stream Controller (for abort tests)

/// Cooperative producer for the ``MockOpenAIServer/ScriptedResponse/controllable``
/// case. Tests call ``sendFrame`` / ``finish`` to drive a streaming response
/// in lock-step with the client, enabling deterministic abort tests without
/// arbitrary sleeps.
///
/// Thread-safe via an internal lock + condition variable. The I/O queue
/// thread calls ``nextChunkSync()`` which blocks until the test produces
/// a chunk or closes the controller.
final class StreamController: @unchecked Sendable {
    enum Chunk: Sendable {
        case frame(String) // A `data: {...}\n\n` JSON payload.
        case done          // Emits `data: [DONE]\n\n`.
        case close         // Closes the connection without a DONE terminator.
    }

    private let lock = NSCondition()
    private var pending: [Chunk] = []
    private var closed = false

    init() {}

    /// Streams one `data: {...}` SSE frame to the client.
    func sendFrame(_ json: String) {
        lock.lock()
        pending.append(.frame(json))
        lock.signal()
        lock.unlock()
    }

    /// Emits `data: [DONE]\n\n` and closes the connection.
    func finish() {
        lock.lock()
        pending.append(.done)
        pending.append(.close)
        closed = true
        lock.broadcast()
        lock.unlock()
    }

    /// Aborts the response server-side without sending `[DONE]`.
    func close() {
        lock.lock()
        pending.append(.close)
        closed = true
        lock.broadcast()
        lock.unlock()
    }

    /// Blocking pull from the I/O queue.
    func nextChunkSync() -> Chunk? {
        lock.lock()
        defer { lock.unlock() }
        while pending.isEmpty, !closed {
            lock.wait()
        }
        if !pending.isEmpty {
            return pending.removeFirst()
        }
        return nil
    }
}

// MARK: - HTTP Request Reader

private struct HTTPRequest {
    let method: String
    let path: String
    let version: String
    let headers: [String: String]
    let body: Data

    /// Reads a full HTTP/1.1 request (headers + content-length body) from a
    /// socket file descriptor. Supports what the real OpenAI client emits:
    /// `POST /v1/chat/completions` with a Content-Length body, and simple
    /// `GET` requests with no body.
    static func read(fd: Int32) throws -> HTTPRequest {
        var buffer = Data()

        while true {
            let chunk = try recv(fd: fd, max: 4_096)
            if chunk.isEmpty {
                throw MockServerError.malformedRequest
            }
            buffer.append(chunk)

            if let range = rangeOfDoubleCRLF(in: buffer) {
                let headerData = buffer.prefix(upTo: range.lowerBound)
                let bodyStart = range.upperBound
                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    throw MockServerError.malformedRequest
                }
                let (line1, headers) = try parseHeaderLines(headerString)
                let parts = line1.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3 else { throw MockServerError.malformedRequest }
                let method = String(parts[0])
                let path = String(parts[1])
                let version = String(parts[2])

                var body = Data(buffer[bodyStart...])
                if let lengthString = headers.first(where: { $0.key.lowercased() == "content-length" })?.value,
                   let expected = Int(lengthString.trimmingCharacters(in: .whitespaces)),
                   expected > 0 {
                    while body.count < expected {
                        let more = try recv(fd: fd, max: 4_096)
                        if more.isEmpty {
                            throw MockServerError.malformedRequest
                        }
                        body.append(more)
                    }
                    if body.count > expected {
                        body = body.prefix(expected)
                    }
                }

                return HTTPRequest(
                    method: method,
                    path: path,
                    version: version,
                    headers: headers,
                    body: body,
                )
            }

            if buffer.count > 64 * 1_024 {
                throw MockServerError.malformedRequest
            }
        }
    }

    private static func recv(fd: Int32, max: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: max)
        let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
            Darwin.recv(fd, buf.baseAddress, buf.count, 0)
        }
        if n < 0 {
            if errno == EINTR { return try recv(fd: fd, max: max) }
            throw MockServerError.malformedRequest
        }
        if n == 0 { return Data() }
        return Data(buffer.prefix(n))
    }

    private static func rangeOfDoubleCRLF(in data: Data) -> Range<Data.Index>? {
        let marker = Data("\r\n\r\n".utf8)
        return data.range(of: marker)
    }

    private static func parseHeaderLines(_ raw: String) throws -> (String, [String: String]) {
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { throw MockServerError.malformedRequest }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return (first, headers)
    }
}
