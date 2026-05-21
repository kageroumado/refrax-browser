import Foundation
import Testing

@testable import Refrax

// MARK: - Integration Tests

/// Wire-level integration tests: real HTTP between ``OpenAICompatibleClient``
/// and a scripted ``MockOpenAIServer`` running in-process on an ephemeral
/// loopback port.
///
/// These tests verify:
/// - Exact headers sent (Authorization, OpenRouter attribution, Content-Type)
/// - Exact body shape (model, stream: true, stream_options.include_usage,
///   OpenAI tools schema rather than Anthropic input_schema, role:"tool"
///   follow-up messages)
/// - End-to-end delta delivery through the real SSE path
/// - Tool-call fragment accumulation
/// - Error surfacing for 401/429/etc.
/// - Local-server compatibility (no Authorization header)
/// - Abort mid-stream
@Suite("OpenAICompatibleClient — end-to-end integration", .tags(.agentMultiProvider), .serialized)
struct OpenAICompatibleClientIntegrationTests {
    // MARK: - Helpers

    /// Collects streaming text deltas from the client as they arrive, and
    /// resolves once the stream reaches a terminal state (final/error/aborted).
    @MainActor
    final class EventCollector {
        struct Snapshot: Sendable {
            let deltas: [String]
            let finalText: String?
            let finalTool: [ToolUseSnapshot]
            let errorMessage: String?
            let wasAborted: Bool
            let stopReason: String?
            let usage: (input: Int?, output: Int?, total: Int?)?
        }

        struct ToolUseSnapshot: Sendable {
            let id: String
            let name: String
        }

        private var deltas: [String] = []
        private var finalText: String?
        private var finalTool: [ToolUseSnapshot] = []
        private var errorMessage: String?
        private var wasAborted = false
        private var stopReason: String?
        private var usage: (input: Int?, output: Int?, total: Int?)?
        private var terminalWaiters: [CheckedContinuation<Snapshot, Never>] = []
        private var isTerminal = false

        /// Receives a payload emitted by the client. Must be called on the MainActor.
        func ingest(_ payload: ChatEventPayload) {
            switch payload.state {
            case .delta:
                if let message = payload.message,
                   let block = message.content.first(where: { $0.type == "text" }),
                   let text = block.text {
                    deltas.append(text)
                }
            case .final:
                if let message = payload.message {
                    finalText = message.content
                        .filter { $0.type == "text" }
                        .compactMap(\.text)
                        .joined()
                    finalTool = message.content
                        .filter { $0.type == "tool_use" }
                        .compactMap { block in
                            guard let id = block.id, let name = block.name else { return nil }
                            return ToolUseSnapshot(id: id, name: name)
                        }
                }
                stopReason = payload.stopReason
                if let usage = payload.usage {
                    self.usage = (usage.input, usage.output, usage.totalTokens)
                }
                resolve()
            case .error:
                errorMessage = payload.errorMessage
                resolve()
            case .aborted:
                wasAborted = true
                resolve()
            }
        }

        /// Suspends until the stream terminates (final/error/aborted).
        func waitForTerminal() async -> Snapshot {
            if isTerminal { return snapshot() }
            return await withCheckedContinuation { continuation in
                terminalWaiters.append(continuation)
            }
        }

        private func resolve() {
            isTerminal = true
            let snap = snapshot()
            for waiter in terminalWaiters {
                waiter.resume(returning: snap)
            }
            terminalWaiters.removeAll()
        }

        private func snapshot() -> Snapshot {
            Snapshot(
                deltas: deltas,
                finalText: finalText,
                finalTool: finalTool,
                errorMessage: errorMessage,
                wasAborted: wasAborted,
                stopReason: stopReason,
                usage: usage,
            )
        }

        /// Test-only read for wait-until predicates.
        func currentDeltas() -> [String] { deltas }
    }

    /// Constructs a client pointing at the given mock server. Skips the
    /// factory path so tests don't touch Keychain.
    @MainActor
    private func makeClient(
        server: MockOpenAIServer,
        baseURL: URL,
        apiKey: String?,
        providerKind: AgentProviderKind,
        extraHeaders: [String: String] = [:],
        model: String = "test-model",
        providerName: String = "Test",
    ) -> OpenAICompatibleClient {
        let config = OpenAIProviderConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            extraHeaders: extraHeaders,
            providerName: providerName,
        )
        // Unique session id per test — avoids ConversationStore cross-test pollution.
        let sessionId = "integration-\(UUID().uuidString)"
        return OpenAICompatibleClient(
            providerKind: providerKind,
            config: config,
            model: model,
            maxCompletionTokens: 128,
            sessionId: sessionId,
        )
    }

    /// Connects the client and installs a collector + minimal system-prompt
    /// builder so `sendChatMessage` passes its `notConfigured` guard.
    @MainActor
    private func prepare(client: OpenAICompatibleClient) async throws -> EventCollector {
        let collector = EventCollector()

        await client.setSystemPromptBuilder { @MainActor in
            ClaudeSystemPrompt.Content(staticPart: "You are a test agent.", dynamicPart: nil)
        }

        await client.setChatEventHandler { @Sendable payload in
            Task { @MainActor in
                collector.ingest(payload)
            }
        }

        try await client.connect()
        return collector
    }

    /// Spins up a server + cleans it up. Each test owns its own server so
    /// scheduled responses and recorded requests don't leak across tests.
    @MainActor
    private func withServer<T>(_ body: @MainActor (MockOpenAIServer) async throws -> T) async throws -> T {
        let server = try MockOpenAIServer.start()
        do {
            let result = try await body(server)
            await server.stop()
            return result
        } catch {
            await server.stop()
            throw error
        }
    }

    // MARK: - 1. Simple streamed message round-trip

    @Test("Streams text deltas end-to-end through real HTTP")
    @MainActor
    func simpleStreamedRoundTrip() async throws {
        try await withServer { server in
            server.scheduleResponse(.streamText(["Hello ", "world!"]))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "TESTKEY",
                providerKind: .openAI,
                model: "gpt-5",
            )
            let collector = try await prepare(client: client)

            _ = try await client.sendChatMessage(
                sessionKey: "test",
                message: "Hi",
                attachments: nil,
            )

            let snapshot = await collector.waitForTerminal()

            // (a) Request was delivered with correct headers + body.
            let requests = server.receivedRequests()
            #expect(requests.count == 1)
            let request = try #require(requests.first)
            #expect(request.method == "POST")
            #expect(request.path == "/v1/chat/completions")
            #expect(request.header("Authorization") == "Bearer TESTKEY")
            #expect(request.header("Content-Type") == "application/json")

            let body = try #require(request.bodyJSON)
            #expect(body["model"] as? String == "gpt-5")
            #expect(body["stream"] as? Bool == true)
            let streamOptions = try #require(body["stream_options"] as? [String: Any])
            #expect(streamOptions["include_usage"] as? Bool == true)

            // (b) Deltas were delivered in order, and the final text is assembled.
            #expect(snapshot.deltas == ["Hello ", "Hello world!"])
            #expect(snapshot.finalText == "Hello world!")
            #expect(snapshot.errorMessage == nil)
        }
    }

    // MARK: - 2. OpenRouter attribution headers

    @Test("OpenRouter client sends attribution headers and exact model slug")
    @MainActor
    func openRouterAttributionHeaders() async throws {
        try await withServer { server in
            server.scheduleResponse(.streamText(["Ok"]))

            // Match what AgentClientFactory.makeOpenRouterConfig produces —
            // we construct the config directly to avoid Keychain dependence.
            let extraHeaders = [
                "HTTP-Referer": "https://refrax.website",
                "X-Title": "Refrax",
            ]
            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "OR-TESTKEY",
                providerKind: .openRouter,
                extraHeaders: extraHeaders,
                model: "anthropic/claude-opus-4.6",
                providerName: "OpenRouter",
            )
            let collector = try await prepare(client: client)

            _ = try await client.sendChatMessage(sessionKey: "test", message: "Hi", attachments: nil)
            _ = await collector.waitForTerminal()

            let requests = server.receivedRequests()
            let request = try #require(requests.first)
            #expect(request.header("HTTP-Referer") == "https://refrax.website")
            #expect(request.header("X-Title") == "Refrax")
            #expect(request.header("Authorization") == "Bearer OR-TESTKEY")

            let body = try #require(request.bodyJSON)
            #expect(body["model"] as? String == "anthropic/claude-opus-4.6")
        }
    }

    // MARK: - 3. Tool-call round-trip

    @Test("Sends OpenAI tool schema and decodes streamed tool call into canonical event")
    @MainActor
    func toolCallRoundTrip() async throws {
        try await withServer { server in
            // First response: a single tool call. The client will execute the
            // tool via our injected executor, then issue a second request
            // carrying the role:"tool" result.
            server.scheduleResponse(.streamToolCall(
                id: "call_read_page",
                name: "read_page",
                argumentsJSON: #"{"url":"https://example.com"}"#,
            ))
            // Second response: a simple text reply so the agentic loop terminates.
            server.scheduleResponse(.streamText(["done"]))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "TESTKEY",
                providerKind: .openAI,
            )

            // Inject a tool definition mirroring Refrax's canonical shape.
            let tool = AgentToolDefinition(
                name: "read_page",
                description: "Read a page by URL.",
                inputSchema: [
                    "type": "object",
                    "properties": ["url": ["type": "string"]],
                    "required": ["url"],
                ],
            )
            await client.setToolDefinitions([tool])

            // Executor returns a canned success so the client advances.
            await client.setToolExecutor { @MainActor _, _ in
                ToolOutput.success("Page contents here")
            }

            let collector = try await prepare(client: client)
            _ = try await client.sendChatMessage(sessionKey: "test", message: "Read it", attachments: nil)

            let snapshot = await collector.waitForTerminal()
            let requests = server.receivedRequests()

            // Two POSTs: first with the user message, second with the tool result.
            #expect(requests.count == 2)

            // (a) Outgoing tools array is OpenAI-shaped.
            let firstBody = try #require(requests[0].bodyJSON)
            let tools = try #require(firstBody["tools"] as? [[String: Any]])
            #expect(tools.count == 1)
            let firstTool = tools[0]
            #expect(firstTool["type"] as? String == "function")
            let function = try #require(firstTool["function"] as? [String: Any])
            #expect(function["name"] as? String == "read_page")
            #expect(function["parameters"] is [String: Any])
            // input_schema is Anthropic-only — must NOT appear at either level.
            #expect(firstTool["input_schema"] == nil)
            #expect(function["input_schema"] == nil)

            // (b) Client decoded the tool call and recorded it in the final message.
            #expect(snapshot.finalTool.count == 1)
            #expect(snapshot.finalTool.first?.name == "read_page")

            // (c) Second request carries role:"tool" + correct tool_call_id.
            let secondBody = try #require(requests[1].bodyJSON)
            let secondMessages = try #require(secondBody["messages"] as? [[String: Any]])
            let toolMessage = try #require(secondMessages.first { ($0["role"] as? String) == "tool" })
            #expect(toolMessage["tool_call_id"] as? String == "call_read_page")
            #expect(toolMessage["content"] as? String == "Page contents here")
        }
    }

    // MARK: - 4. Partial tool-call argument accumulation

    @Test("Concatenates tool-call argument fragments by index before parsing")
    @MainActor
    func toolCallFragmentAccumulation() async throws {
        try await withServer { server in
            server.scheduleResponse(.streamToolCallFragmented(
                id: "call_frag",
                name: "read_page",
                argumentFragments: ["{\"url", "\": \"htt", "ps://ex", "ample.com\"}"],
            ))
            // Follow-up: simple text ack so the loop completes.
            server.scheduleResponse(.streamText(["ok"]))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "TESTKEY",
                providerKind: .openAI,
            )

            // Capture what the executor sees — this is where the parsed
            // arguments are observable to the caller.
            let capturedURL = LockedBox<String?>(nil)
            let tool = AgentToolDefinition(
                name: "read_page",
                description: "Read a page by URL.",
                inputSchema: [
                    "type": "object",
                    "properties": ["url": ["type": "string"]],
                    "required": ["url"],
                ],
            )
            await client.setToolDefinitions([tool])
            await client.setToolExecutor { @MainActor _, input in
                if case let .string(value) = input["url"] {
                    capturedURL.value = value
                }
                return .success("ok")
            }

            let collector = try await prepare(client: client)
            _ = try await client.sendChatMessage(sessionKey: "test", message: "Read fragmented", attachments: nil)
            _ = await collector.waitForTerminal()

            #expect(capturedURL.value == "https://example.com")
        }
    }

    // MARK: - 5. Error handling — 401

    @Test("401 surfaces a typed authentication error")
    @MainActor
    func errorHandling401() async throws {
        try await withServer { server in
            server.scheduleResponse(.error(
                status: 401,
                body: #"{"error":{"message":"Invalid API key","type":"invalid_request_error","code":"invalid_api_key"}}"#,
            ))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "BADKEY",
                providerKind: .openAI,
            )
            let collector = try await prepare(client: client)

            _ = try await client.sendChatMessage(sessionKey: "test", message: "Hi", attachments: nil)
            let snapshot = await collector.waitForTerminal()

            let error = try #require(snapshot.errorMessage)
            #expect(error.localizedCaseInsensitiveContains("authentication") || error.contains("API key"))
        }
    }

    // MARK: - 6. Error handling — 429 with Retry-After

    @Test("429 is surfaced as a rate-limit error")
    @MainActor
    func errorHandling429() async throws {
        try await withServer { server in
            server.scheduleResponse(.error(
                status: 429,
                body: #"{"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}"#,
                headers: ["Retry-After": "42"],
            ))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "TESTKEY",
                providerKind: .openAI,
            )
            let collector = try await prepare(client: client)

            _ = try await client.sendChatMessage(sessionKey: "test", message: "Hi", attachments: nil)
            let snapshot = await collector.waitForTerminal()

            let error = try #require(snapshot.errorMessage)
            #expect(error.localizedCaseInsensitiveContains("rate limit"))
        }
    }

    // MARK: - 7. [DONE] handling + usage final chunk

    @Test("Handles final usage-only chunk followed by [DONE] without crashing")
    @MainActor
    func usageFinalChunkHandling() async throws {
        try await withServer { server in
            let usage = MockOpenAIServer.UsageStub(
                promptTokens: 12,
                completionTokens: 5,
                totalTokens: 17,
            )
            server.scheduleResponse(.streamTextWithUsage(["Hello ", "world"], usage: usage))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "TESTKEY",
                providerKind: .openAI,
            )
            let collector = try await prepare(client: client)

            _ = try await client.sendChatMessage(sessionKey: "test", message: "Hi", attachments: nil)
            let snapshot = await collector.waitForTerminal()

            #expect(snapshot.finalText == "Hello world")
            #expect(snapshot.errorMessage == nil)
            // The client propagates usage when present.
            let usageSnap = try #require(snapshot.usage)
            #expect(usageSnap.input == 12)
            #expect(usageSnap.output == 5)
        }
    }

    // MARK: - 8. Local-server compat (no Authorization header)

    @Test("Custom provider without auth sends no Authorization header")
    @MainActor
    func customProviderNoAuthHeader() async throws {
        try await withServer { server in
            server.scheduleResponse(.streamText(["ok"]))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: nil, // Simulates agentCustomRequiresAuth == false
                providerKind: .custom,
                model: "llama3.1:latest",
                providerName: "Local Ollama",
            )
            let collector = try await prepare(client: client)

            _ = try await client.sendChatMessage(sessionKey: "test", message: "Hi", attachments: nil)
            _ = await collector.waitForTerminal()

            let requests = server.receivedRequests()
            let request = try #require(requests.first)
            #expect(request.header("Authorization") == nil)
        }
    }

    // MARK: - 9. Abort mid-stream

    @Test("abortChat stops event emission and drops the connection")
    @MainActor
    func abortMidStream() async throws {
        try await withServer { server in
            let controller = StreamController()
            server.scheduleResponse(.controllable(controller))

            let client = makeClient(
                server: server,
                baseURL: server.baseURL,
                apiKey: "TESTKEY",
                providerKind: .openAI,
            )
            let collector = try await prepare(client: client)

            let runId = try await client.sendChatMessage(sessionKey: "test", message: "Slow", attachments: nil)

            // Wait for the POST to arrive before driving the stream.
            _ = await server.waitForNextRequest()

            // Emit one delta so the client has something to forward.
            controller.sendFrame(
                #"{"choices":[{"index":0,"delta":{"content":"partial"},"finish_reason":null}]}"#,
            )

            // Wait for the client to observe the first delta before we abort —
            // this avoids racing the HTTP response arrival.
            try await waitUntil { !collector.currentDeltas().isEmpty }

            // Abort from the client side.
            try await client.abortChat(sessionKey: "test", runId: runId)

            // Server-side: close the connection so we can observe disconnect.
            controller.close()

            let snapshot = await collector.waitForTerminal()
            #expect(snapshot.wasAborted)
            #expect(snapshot.errorMessage == nil || snapshot.wasAborted)

            // No second delta made it through — the post-abort `sendFrame`
            // was never issued by the server (we closed instead).
            #expect(snapshot.deltas == ["partial"])
        }
    }

    // MARK: - Wait Helpers

    /// Polls a predicate until it returns true. Uses `Task.yield()` — no
    /// sleeps, no fixed intervals. Fails fast if the predicate never becomes
    /// true within a generous timeout.
    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ predicate: @MainActor () -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            await Task.yield()
        }
        throw MockServerError.timeout
    }
}

// MARK: - Thread-Safe Box

/// Minimal MainActor-isolated box so tool-executor closures can smuggle a
/// captured value out for assertions. Use only from the MainActor.
@MainActor
final class LockedBox<T: Sendable>: Sendable {
    var value: T

    init(_ initial: T) {
        self.value = initial
    }
}
