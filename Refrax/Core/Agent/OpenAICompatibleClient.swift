import Foundation
import OSLog

/// Provider configuration for ``OpenAICompatibleClient``.
///
/// Same wire format (OpenAI Chat Completions) regardless of endpoint —
/// OpenAI, OpenRouter, Ollama, LM Studio, llama.cpp, vLLM, and any
/// other compatible server are all modelled by varying this struct.
nonisolated struct OpenAIProviderConfig: Sendable {
    /// Base URL, up to and including the `/v1` prefix. `/chat/completions`
    /// and `/models` are appended at request time.
    let baseURL: URL

    /// Bearer token. `nil` suppresses the `Authorization` header, which is
    /// appropriate for local servers that don't authenticate.
    let apiKey: String?

    /// Extra headers (e.g., OpenRouter's `HTTP-Referer` + `X-Title`).
    let extraHeaders: [String: String]

    /// Human-readable provider name, for logging only.
    let providerName: String

    init(baseURL: URL, apiKey: String?, extraHeaders: [String: String] = [:], providerName: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.providerName = providerName
    }
}

/// Chat client for OpenAI-compatible Chat Completions endpoints.
///
/// Speaks the `POST {base}/v1/chat/completions` wire format with SSE
/// streaming, tool-calling, and image content. Conforms to
/// ``AgentChatClientProtocol`` so the rest of Refrax treats it identically
/// to ``ClaudeDirectClient``.
///
/// ## Supported servers
/// - `api.openai.com`
/// - `openrouter.ai/api`
/// - Any local OpenAI-compatible server — Ollama, LM Studio, llama.cpp, vLLM
///
/// ## Architecture
///
/// The conversation history is kept in Refrax's Anthropic-canonical form
/// (``AnthropicMessage``). On each request, ``OpenAIToolAdapter`` translates
/// it to OpenAI wire format; on streaming, tool-call fragments are
/// accumulated by `index` and parsed into the canonical form when the
/// stream finishes with `finish_reason == "tool_calls"`.
actor OpenAICompatibleClient: AgentChatClientProtocol {
    // MARK: - Types

    nonisolated enum ClientError: Error, LocalizedError {
        case noCredential
        case notConfigured
        case requestFailed(statusCode: Int, message: String)
        case streamError(String)

        var errorDescription: String? {
            switch self {
            case .noCredential: "No API key configured"
            case .notConfigured: "Agent tools not yet configured — please wait a moment and try again"
            case let .requestFailed(code, message): "API error (\(code)): \(message)"
            case let .streamError(message): "Stream error: \(message)"
            }
        }
    }

    // MARK: - Configuration

    private let providerKind: AgentProviderKind
    private let config: OpenAIProviderConfig
    private let model: String
    private let maxCompletionTokens: Int

    // MARK: - State

    private(set) var connectionState: AgentConnectionState = .disconnected
    private var chatEventHandler: (@Sendable (ChatEventPayload) -> Void)?
    private var connectionStateHandler: (@Sendable (AgentConnectionState) -> Void)?

    private var activeStreamTask: Task<Void, Never>?

    /// Conversation history in canonical (Anthropic-shaped) form.
    private var conversationHistory: [AnthropicMessage] = []

    private let sessionId: String

    private var systemPromptBuilder: (@MainActor @Sendable () -> ClaudeSystemPrompt.Content)?
    private var toolDefinitions: [AgentToolDefinition]?
    private var toolExecutor: (@MainActor @Sendable (String, [String: AnthropicJSONValue]) async throws -> ToolOutput)?

    func setSystemPromptBuilder(_ builder: @escaping @MainActor @Sendable () -> ClaudeSystemPrompt.Content) {
        systemPromptBuilder = builder
    }

    func setToolDefinitions(_ definitions: [AgentToolDefinition]) {
        toolDefinitions = definitions
    }

    func setToolExecutor(
        _ executor: @escaping @MainActor @Sendable (String, [String: AnthropicJSONValue]) async throws -> ToolOutput,
    ) {
        toolExecutor = executor
    }

    /// Maximum agentic loop iterations to prevent runaway tool calls.
    private let maxToolIterations = 25

    // MARK: - Init

    init(
        providerKind: AgentProviderKind,
        config: OpenAIProviderConfig,
        model: String,
        maxCompletionTokens: Int,
        sessionId: String? = nil,
    ) {
        self.providerKind = providerKind
        self.config = config
        self.model = model
        self.maxCompletionTokens = maxCompletionTokens
        self.sessionId = sessionId ?? "openai-\(providerKind.rawValue)"
    }

    // MARK: - Connection

    func connect() async throws {
        // Local servers legitimately have no API key; only flag missing key
        // when the provider definitionally requires one.
        if providerKind != .custom, (config.apiKey?.isEmpty ?? true) {
            throw ClientError.noCredential
        }

        updateConnectionState(.connected)
        conversationHistory = ConversationStore.load(sessionId: sessionId)
        repairConversationHistory()
        Logger.info("[\(config.providerName)] Connected, loaded \(conversationHistory.count) persisted messages", category: Logger.agent)
    }

    func disconnect() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        updateConnectionState(.disconnected)
    }

    // MARK: - Chat Operations

    func sendChatMessage(
        sessionKey _: String,
        message: String,
        attachments: [ChatSendParams.ChatAttachment]?,
    ) async throws -> String {
        guard connectionState.isConnected else { throw ClientError.noCredential }
        guard systemPromptBuilder != nil else { throw ClientError.notConfigured }

        let runId = UUID().uuidString

        var blocks: [AnthropicContentBlock] = []
        if let attachments {
            for attachment in attachments {
                blocks.append(.image(mediaType: attachment.mimeType, data: attachment.content))
            }
        }
        blocks.append(.text(message))

        let userMessage = AnthropicMessage(role: "user", content: blocks, createdAt: Date())
        conversationHistory.append(userMessage)

        activeStreamTask = Task { [weak self] in
            await self?.performStreamingRequest(runId: runId)
        }

        return runId
    }

    func fetchChatHistory(sessionKey _: String, limit: Int) async throws -> ChatHistoryResponse {
        let historyMessages = conversationHistory.suffix(limit).map { msg in
            ChatHistoryResponse.HistoryMessage(
                role: msg.role,
                content: msg.content.compactMap { block -> ChatHistoryResponse.HistoryMessage.ContentBlock? in
                    switch block {
                    case let .text(text):
                        return .init(type: "text", text: text, source: nil)
                    case let .image(mediaType, data):
                        return .init(
                            type: "image",
                            text: nil,
                            source: .init(type: "base64", mediaType: mediaType, data: data),
                        )
                    case .toolUse, .toolResult:
                        return nil
                    }
                },
                timestamp: Int(msg.createdAt.timeIntervalSince1970 * 1_000),
            )
        }
        return ChatHistoryResponse(messages: historyMessages, thinkingLevel: nil)
    }

    func abortChat(sessionKey _: String, runId: String) async throws {
        activeStreamTask?.cancel()
        activeStreamTask = nil

        let payload = ChatEventPayload(
            runId: runId,
            sessionKey: sessionId,
            seq: 0,
            state: .aborted,
            message: nil,
            errorMessage: nil,
            usage: nil,
            stopReason: "aborted",
        )
        chatEventHandler?(payload)
    }

    func setChatEventHandler(_ handler: @escaping @Sendable (ChatEventPayload) -> Void) {
        chatEventHandler = handler
    }

    func setConnectionStateHandler(_ handler: @escaping @Sendable (AgentConnectionState) -> Void) {
        connectionStateHandler = handler
    }

    func clearConversation() {
        conversationHistory.removeAll()
        ConversationStore.clear(sessionId: sessionId)
    }

    // MARK: - History Repair

    private func repairConversationHistory() {
        guard !conversationHistory.isEmpty else { return }
        let lastMessage = conversationHistory.last!
        guard lastMessage.role == "assistant" else { return }

        let toolUseIDs = lastMessage.content.compactMap { block -> String? in
            if case let .toolUse(id, _, _) = block { return id }
            return nil
        }
        guard !toolUseIDs.isEmpty else { return }

        let resultBlocks: [AnthropicContentBlock] = toolUseIDs.map { id in
            .toolResult(
                toolUseId: id,
                content: [.text("Tool execution was interrupted (app crash). Please retry if needed.")],
                isError: true,
            )
        }
        conversationHistory.append(AnthropicMessage(role: "user", content: resultBlocks, createdAt: Date()))
        persistConversation()
        Logger.info("[\(config.providerName)] Repaired \(toolUseIDs.count) orphaned tool_use block(s)", category: Logger.agent)
    }

    // MARK: - Streaming Request

    private func performStreamingRequest(runId: String) async {
        var iterationCount = 0
        var allToolBlocks: [ChatEventPayload.ChatMessage.ContentBlock] = []

        while iterationCount < maxToolIterations {
            iterationCount += 1

            let request: URLRequest
            do {
                request = try await buildRequest()
            } catch {
                emitError(runId: runId, message: "Failed to build request: \(error.localizedDescription)")
                return
            }

            let result = await executeStreamingRequest(request: request, runId: runId)

            switch result {
            case let .completed(assistantMessage, usage, stopReason):
                conversationHistory.append(assistantMessage)

                if stopReason == "tool_use", let executor = toolExecutor {
                    let toolResults = await executeTools(from: assistantMessage, executor: executor, runId: runId)
                    if let toolResultMessage = toolResults {
                        for block in assistantMessage.content {
                            if case let .toolUse(id, name, _) = block {
                                allToolBlocks.append(.init(type: "tool_use", text: nil, id: id, name: name))
                            }
                        }
                        for block in toolResultMessage.content {
                            if case let .toolResult(toolUseId, content, isError) = block {
                                let displayText = content.compactMap(\.textValue).first ?? ""
                                allToolBlocks.append(.init(
                                    type: "tool_result", text: displayText,
                                    toolUseId: toolUseId, isError: isError,
                                ))
                            }
                        }
                        conversationHistory.append(toolResultMessage)
                        persistConversation()
                        continue
                    }
                }

                persistConversation()

                var finalContentBlocks: [ChatEventPayload.ChatMessage.ContentBlock] = allToolBlocks
                for block in assistantMessage.content {
                    if case let .text(text) = block {
                        finalContentBlocks.append(.init(type: "text", text: text))
                    }
                }

                let finalPayload = ChatEventPayload(
                    runId: runId,
                    sessionKey: sessionId,
                    seq: 0,
                    state: .final,
                    message: ChatEventPayload.ChatMessage(
                        role: "assistant",
                        content: finalContentBlocks,
                        timestamp: Int(Date().timeIntervalSince1970 * 1_000),
                    ),
                    errorMessage: nil,
                    usage: usage.map { ChatEventPayload.ChatUsage(
                        input: $0.inputTokens,
                        output: $0.outputTokens,
                        totalTokens: $0.inputTokens + $0.outputTokens,
                    ) },
                    stopReason: stopReason,
                )
                chatEventHandler?(finalPayload)
                return

            case let .error(message):
                emitError(runId: runId, message: message)
                return

            case .cancelled:
                return
            }
        }

        emitError(runId: runId, message: "Tool loop exceeded \(maxToolIterations) iterations")
    }

    // MARK: - Request Building

    private func buildRequest() async throws -> URLRequest {
        let url = config.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in config.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]

        var messagesArray: [[String: Any]] = []

        // System prompt — flatten static + dynamic since OpenAI has no
        // per-block cache control.
        if let builder = systemPromptBuilder {
            let prompt = await MainActor.run { builder() }
            messagesArray.append(["role": "system", "content": prompt.fullText])
        }
        messagesArray.append(contentsOf: OpenAIToolAdapter.encodeMessages(conversationHistory))
        body["messages"] = messagesArray

        if let definitions = toolDefinitions, !definitions.isEmpty {
            body["tools"] = OpenAIToolAdapter.toolsJSON(from: definitions)
            body["tool_choice"] = "auto"
            body["parallel_tool_calls"] = true
        }

        // max_completion_tokens — never max_tokens. Reasoning models only
        // accept the new field; non-reasoning models accept both, so using
        // the new name is the safe default.
        body["max_completion_tokens"] = maxCompletionTokens

        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw ClientError.streamError("Failed to encode request body")
        }
        request.httpBody = data
        return request
    }

    // MARK: - SSE Stream

    private enum StreamResult {
        case completed(AnthropicMessage, usage: AgentMessage.TokenUsage?, stopReason: String?)
        case error(String)
        case cancelled
    }

    private func executeStreamingRequest(request: URLRequest, runId: String) async -> StreamResult {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse

        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            return .error("Invalid response")
        }

        if http.statusCode != 200 {
            var body = ""
            do {
                for try await line in bytes.lines {
                    body += line
                    if body.count > 2_000 { break }
                }
            } catch {}

            switch http.statusCode {
            case 401:
                return .error("Authentication failed — check your API key")
            case 402:
                return .error("Insufficient credits (\(config.providerName))")
            case 404:
                return .error("Model '\(model)' not found on \(config.providerName)")
            case 429:
                return .error("Rate limited — please wait a moment and try again")
            default:
                let extracted = extractErrorMessage(from: body) ?? String(body.prefix(300))
                return .error("API error (\(http.statusCode)): \(extracted)")
            }
        }

        let decoder = OpenAIStreamDecoder()
        var seq = 0

        do {
            for try await line in bytes.lines {
                guard !Task.isCancelled else { return .cancelled }
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }

                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                for event in decoder.consume(chunk: json) {
                    if case let .textDelta(accumulated) = event {
                        seq += 1
                        let streamPayload = ChatEventPayload(
                            runId: runId,
                            sessionKey: sessionId,
                            seq: seq,
                            state: .delta,
                            message: ChatEventPayload.ChatMessage(
                                role: "assistant",
                                content: [.init(type: "text", text: accumulated)],
                                timestamp: nil,
                            ),
                            errorMessage: nil,
                            usage: nil,
                            stopReason: nil,
                        )
                        chatEventHandler?(streamPayload)
                    }
                }
            }
        } catch {
            if Task.isCancelled { return .cancelled }
            return .error("Stream error: \(error.localizedDescription)")
        }

        let decoded = decoder.finalize()

        var contentBlocks: [AnthropicContentBlock] = []
        if !decoded.text.isEmpty {
            contentBlocks.append(.text(decoded.text))
        }
        for call in decoded.toolCalls {
            let input = OpenAIToolAdapter.decodeArgumentsJSON(call.argumentsJSON)
            contentBlocks.append(.toolUse(id: call.id, name: call.name, input: input))
        }

        let assistantMessage = AnthropicMessage(role: "assistant", content: contentBlocks, createdAt: Date())
        return .completed(assistantMessage, usage: decoded.usage, stopReason: decoded.stopReason)
    }

    // MARK: - Tool Execution

    private func executeTools(
        from assistantMessage: AnthropicMessage,
        executor: @MainActor @Sendable (String, [String: AnthropicJSONValue]) async throws -> ToolOutput,
        runId: String,
    ) async -> AnthropicMessage? {
        var resultBlocks: [AnthropicContentBlock] = []

        for block in assistantMessage.content {
            guard case let .toolUse(id, name, input) = block else { continue }

            let statusPayload = ChatEventPayload(
                runId: runId,
                sessionKey: sessionId,
                seq: 0,
                state: .delta,
                message: ChatEventPayload.ChatMessage(
                    role: "assistant",
                    content: [.init(type: "tool_use", text: nil, id: id, name: name)],
                    timestamp: nil,
                ),
                errorMessage: nil,
                usage: nil,
                stopReason: nil,
            )
            chatEventHandler?(statusPayload)

            do {
                let output = try await executor(name, input)
                resultBlocks.append(.toolResult(
                    toolUseId: id,
                    content: output.content.map(\.toToolResultContent),
                    isError: output.isError,
                ))
            } catch {
                resultBlocks.append(.toolResult(
                    toolUseId: id,
                    content: [.text("Error: \(error.localizedDescription)")],
                    isError: true,
                ))
            }
        }

        guard !resultBlocks.isEmpty else { return nil }
        return AnthropicMessage(role: "user", content: resultBlocks, createdAt: Date())
    }

    // MARK: - Helpers

    private func emitError(runId: String, message: String) {
        Logger.error("[\(config.providerName)] \(message)", category: Logger.agent)
        let payload = ChatEventPayload(
            runId: runId,
            sessionKey: sessionId,
            seq: 0,
            state: .error,
            message: nil,
            errorMessage: message,
            usage: nil,
            stopReason: nil,
        )
        chatEventHandler?(payload)
    }

    private func updateConnectionState(_ state: AgentConnectionState) {
        connectionState = state
        connectionStateHandler?(state)
    }

    private func persistConversation() {
        let history = conversationHistory
        let id = sessionId
        Task.detached(priority: .utility) {
            ConversationStore.save(sessionId: id, messages: history)
        }
    }

    private func extractErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}
