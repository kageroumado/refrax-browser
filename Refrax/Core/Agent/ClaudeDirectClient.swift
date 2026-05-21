import Foundation
import OSLog

/// Direct client for the Anthropic Messages API.
///
/// Sends messages directly to `api.anthropic.com` using the user's API key.
/// Handles SSE streaming, conversation history management, and the agentic
/// tool-use loop.
///
/// ## Architecture
///
/// This client manages the full `tool_use → execute → tool_result → continue`
/// cycle locally.
actor ClaudeDirectClient: AgentChatClientProtocol {
    // MARK: - Types

    nonisolated enum ClientError: Error, LocalizedError {
        case noCredential
        case invalidCredential
        case notConfigured
        case requestFailed(statusCode: Int, message: String)
        case streamError(String)

        var errorDescription: String? {
            switch self {
            case .noCredential:
                "No API key configured"
            case .invalidCredential:
                "Invalid API key"
            case .notConfigured:
                "Agent tools not yet configured — please wait a moment and try again"
            case let .requestFailed(code, message):
                "API error (\(code)): \(message)"
            case let .streamError(message):
                "Stream error: \(message)"
            }
        }
    }

    // MARK: - Configuration

    private let model: String
    private let maxTokens: Int

    // MARK: - State

    private(set) var connectionState: AgentConnectionState = .disconnected
    private var chatEventHandler: (@Sendable (ChatEventPayload) -> Void)?
    private var connectionStateHandler: (@Sendable (AgentConnectionState) -> Void)?

    /// Active streaming task (for cancellation).
    private var activeStreamTask: Task<Void, Never>?

    /// Conversation history in Anthropic API format.
    private var conversationHistory: [AnthropicMessage] = []

    /// Session ID for conversation persistence.
    private let sessionId: String

    /// System prompt builder (set externally for tool support).
    private var systemPromptBuilder: (@MainActor @Sendable () -> ClaudeSystemPrompt.Content)?

    /// Tool definitions (set externally for tool support).
    private var toolDefinitions: [AgentToolDefinition]?

    /// Tool executor (set externally for tool support).
    private var toolExecutor: (@MainActor @Sendable (String, [String: AnthropicJSONValue]) async throws -> ToolOutput)?

    func setSystemPromptBuilder(_ builder: @escaping @MainActor @Sendable () -> ClaudeSystemPrompt.Content) {
        systemPromptBuilder = builder
    }

    func setToolDefinitions(_ definitions: [AgentToolDefinition]) {
        toolDefinitions = definitions
    }

    func setToolExecutor(_ executor: @escaping @MainActor @Sendable (String, [String: AnthropicJSONValue]) async throws -> ToolOutput) {
        toolExecutor = executor
    }

    /// Maximum agentic loop iterations to prevent runaway tool calls.
    private let maxToolIterations = 25

    // MARK: - API Constants

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    // MARK: - Initialization

    init(model: String, maxTokens: Int, sessionId: String = "claude-direct") {
        self.model = model
        self.maxTokens = maxTokens
        self.sessionId = sessionId
    }

    // MARK: - Connection

    func connect() async throws {
        guard ClaudeCredentialStore.activeCredential() != nil else {
            throw ClientError.noCredential
        }

        updateConnectionState(.connected)

        // Load persisted conversation and repair if needed
        conversationHistory = ConversationStore.load(sessionId: sessionId)
        repairConversationHistory()
        Logger.info("[ClaudeDirect] Connected, loaded \(conversationHistory.count) persisted messages", category: Logger.agent)
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
        guard connectionState.isConnected else {
            throw ClientError.noCredential
        }

        guard systemPromptBuilder != nil else {
            throw ClientError.notConfigured
        }

        let runId = UUID().uuidString

        // Build user message content blocks
        var contentBlocks: [AnthropicContentBlock] = []

        // Add image attachments
        if let attachments {
            for attachment in attachments {
                contentBlocks.append(.image(
                    mediaType: attachment.mimeType,
                    data: attachment.content,
                ))
            }
        }

        // Add text
        contentBlocks.append(.text(message))

        let userMessage = AnthropicMessage(role: "user", content: contentBlocks, createdAt: Date())
        conversationHistory.append(userMessage)

        // Start streaming in background
        activeStreamTask = Task { [weak self] in
            await self?.performStreamingRequest(runId: runId)
        }

        return runId
    }

    func fetchChatHistory(sessionKey _: String, limit: Int) async throws -> ChatHistoryResponse {
        // Convert local history to ChatHistoryResponse format
        let historyMessages = conversationHistory.suffix(limit).map { msg in
            ChatHistoryResponse.HistoryMessage(
                role: msg.role,
                content: msg.content.compactMap { block -> ChatHistoryResponse.HistoryMessage.ContentBlock? in
                    switch block {
                    case let .text(text):
                        return ChatHistoryResponse.HistoryMessage.ContentBlock(type: "text", text: text, source: nil)
                    case let .image(mediaType, data):
                        let source = ChatHistoryResponse.HistoryMessage.ContentBlock.ImageSource(
                            type: "base64", mediaType: mediaType, data: data,
                        )
                        return ChatHistoryResponse.HistoryMessage.ContentBlock(type: "image", text: nil, source: source)
                    case .toolUse, .toolResult:
                        // Tool blocks are not displayed in history view
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

    // MARK: - Clear Conversation

    /// Clears the conversation history.
    func clearConversation() {
        conversationHistory.removeAll()
        ConversationStore.clear(sessionId: sessionId)
    }

    // MARK: - History Repair

    /// Ensures conversation history is valid for the Anthropic API.
    ///
    /// Every assistant `tool_use` block must be followed by a user message containing
    /// matching `tool_result` blocks. If the app crashes during tool execution (e.g., an
    /// ObjC exception), the assistant message is persisted but the tool_result never is.
    /// This method detects and repairs such orphaned tool_use blocks.
    private func repairConversationHistory() {
        guard !conversationHistory.isEmpty else { return }

        let lastMessage = conversationHistory.last!
        guard lastMessage.role == "assistant" else { return }

        let toolUseIDs = lastMessage.content.compactMap { block -> String? in
            if case let .toolUse(id, _, _) = block { return id }
            return nil
        }
        guard !toolUseIDs.isEmpty else { return }

        // The last message is an assistant with tool_use but no subsequent tool_result.
        // Add synthetic error results so the API doesn't reject the history.
        let resultBlocks: [AnthropicContentBlock] = toolUseIDs.map { id in
            .toolResult(
                toolUseId: id,
                content: [.text("Tool execution was interrupted (app crash). Please retry if needed.")],
                isError: true,
            )
        }
        conversationHistory.append(AnthropicMessage(role: "user", content: resultBlocks, createdAt: Date()))
        persistConversation()
        Logger.info("[ClaudeDirect] Repaired \(toolUseIDs.count) orphaned tool_use block(s)", category: Logger.agent)
    }

    // MARK: - Streaming Request

    private func performStreamingRequest(runId: String) async {
        var iterationCount = 0

        // Accumulated tool blocks across iterations for UI display.
        var allToolBlocks: [ChatEventPayload.ChatMessage.ContentBlock] = []

        // Agentic loop: keep going while Claude wants to use tools
        while iterationCount < maxToolIterations {
            iterationCount += 1

            guard let credential = ClaudeCredentialStore.activeCredential() else {
                emitError(runId: runId, message: "No credential available")
                return
            }

            // Build request
            var request = URLRequest(url: Self.apiURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

            // Auth headers + prompt caching beta
            switch credential {
            case let .apiKey(key):
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
            }

            // Build request body
            var body: [String: Any] = [
                "model": model,
                "max_tokens": maxTokens,
                "stream": true,
            ]

            // System prompt (structured for prompt caching)
            if let builder = systemPromptBuilder {
                let promptContent = await builder()
                var systemBlocks: [[String: Any]] = [
                    [
                        "type": "text",
                        "text": promptContent.staticPart,
                        "cache_control": ["type": "ephemeral"],
                    ],
                ]
                if let dynamic = promptContent.dynamicPart {
                    systemBlocks.append(["type": "text", "text": dynamic])
                }
                body["system"] = systemBlocks
            }

            // Tool definitions (with cache_control on the last tool)
            if let tools = toolDefinitions, !tools.isEmpty {
                var toolDicts = tools.map(\.apiRepresentation)
                // Add code execution tool for programmatic tool calling
                toolDicts.append(["type": "code_execution_20250825", "name": "code_execution"])
                toolDicts[toolDicts.count - 1]["cache_control"] = ["type": "ephemeral"]
                body["tools"] = toolDicts
            }

            // Messages
            body["messages"] = conversationHistory.map { msg -> [String: Any] in
                [
                    "role": msg.role,
                    "content": msg.content.map { block -> [String: Any] in
                        switch block {
                        case let .text(text):
                            return ["type": "text", "text": text]
                        case let .image(mediaType, data):
                            return [
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": mediaType,
                                    "data": data,
                                ],
                            ]
                        case let .toolUse(id, name, input):
                            return [
                                "type": "tool_use",
                                "id": id,
                                "name": name,
                                "input": input.mapValues(\.swiftValue),
                            ]
                        case let .toolResult(toolUseId, content, isError):
                            var result: [String: Any] = [
                                "type": "tool_result",
                                "tool_use_id": toolUseId,
                            ]
                            // Emit array content for mixed text+image, string shorthand for text-only
                            let hasImage = content.contains { $0.isImage }
                            if hasImage {
                                result["content"] = content.map { item -> [String: Any] in
                                    switch item {
                                    case let .text(text):
                                        return ["type": "text", "text": text]
                                    case let .image(mediaType, data):
                                        return [
                                            "type": "image",
                                            "source": [
                                                "type": "base64",
                                                "media_type": mediaType,
                                                "data": data,
                                            ],
                                        ]
                                    }
                                }
                            } else {
                                // Text-only: use string shorthand
                                let text = content.compactMap(\.textValue).joined()
                                result["content"] = text
                            }
                            if isError { result["is_error"] = true }
                            return result
                        }
                    },
                ]
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                emitError(runId: runId, message: "Failed to encode request")
                return
            }
            request.httpBody = jsonData

            // Execute streaming request
            let streamResult = await executeStreamingRequest(request: request, runId: runId)

            switch streamResult {
            case let .completed(assistantMessage, usage, stopReason):
                // Append assistant response to in-memory history
                conversationHistory.append(assistantMessage)

                if stopReason == "tool_use", let executor = toolExecutor {
                    // Don't persist yet — if tool execution crashes (e.g., ObjC exception),
                    // we'd leave an orphaned tool_use without a matching tool_result.
                    // Persist both the assistant and tool_result messages together.
                    let toolResults = await executeTools(from: assistantMessage, executor: executor, runId: runId)
                    if let toolResultMessage = toolResults {
                        // Accumulate tool blocks for UI display
                        for block in assistantMessage.content {
                            if case let .toolUse(id, name, _) = block {
                                allToolBlocks.append(.init(type: "tool_use", text: nil, id: id, name: name))
                            }
                        }
                        for block in toolResultMessage.content {
                            if case let .toolResult(toolUseId, content, isError) = block {
                                let displayText = content.compactMap(\.textValue).first ?? ""
                                allToolBlocks.append(.init(type: "tool_result", text: displayText, toolUseId: toolUseId, isError: isError))
                            }
                        }

                        conversationHistory.append(toolResultMessage)
                        // Now persist both assistant + tool_result atomically
                        persistConversation()
                        // Continue loop — next iteration sends tool results to Claude
                        continue
                    }
                }

                // Non-tool responses or tool_use with no results — safe to persist
                persistConversation()

                // Build final content blocks: tool indicators + text
                var finalContentBlocks: [ChatEventPayload.ChatMessage.ContentBlock] = allToolBlocks
                for block in assistantMessage.content {
                    if case let .text(text) = block {
                        finalContentBlocks.append(.init(type: "text", text: text))
                    }
                }

                // Emit final event
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

        // Exceeded max iterations
        emitError(runId: runId, message: "Tool loop exceeded \(maxToolIterations) iterations")
    }

    // MARK: - SSE Stream Processing

    private enum StreamResult {
        case completed(AnthropicMessage, usage: AgentMessage.TokenUsage?, stopReason: String?)
        case error(String)
        case cancelled
    }

    private func executeStreamingRequest(request: URLRequest, runId: String) async -> StreamResult {
        let asyncBytes: URLSession.AsyncBytes
        let response: URLResponse

        do {
            (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .error("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            // Try to read error body
            var errorBody = ""
            do {
                for try await line in asyncBytes.lines {
                    errorBody += line
                    if errorBody.count > 1_000 { break }
                }
            } catch {}

            if httpResponse.statusCode == 401 {
                return .error("Authentication failed — check your API key")
            }
            if httpResponse.statusCode == 429 {
                return .error("Rate limited — please wait a moment and try again")
            }
            return .error("API error (\(httpResponse.statusCode)): \(errorBody.prefix(200))")
        }

        // Parse SSE stream
        var accumulatedText = ""
        var toolUseBlocks: [(id: String, name: String, inputJSON: String)] = []
        var currentToolId: String?
        var currentToolName: String?
        var currentToolInputJSON = ""
        var usage: AgentMessage.TokenUsage?
        var stopReason: String?
        var seq = 0

        do {
            for try await line in asyncBytes.lines {
                guard !Task.isCancelled else { return .cancelled }

                if line.hasPrefix("data: ") {
                    let data = String(line.dropFirst(6))
                    if data == "[DONE]" { break }

                    guard let eventData = data.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                          let eventType = json["type"] as? String
                    else { continue }

                    switch eventType {
                    case "content_block_start":
                        if let contentBlock = json["content_block"] as? [String: Any],
                           let blockType = contentBlock["type"] as? String {
                            if blockType == "tool_use" {
                                currentToolId = contentBlock["id"] as? String
                                currentToolName = contentBlock["name"] as? String
                                currentToolInputJSON = ""
                            }
                        }

                    case "content_block_delta":
                        if let delta = json["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String {
                            if deltaType == "text_delta", let text = delta["text"] as? String {
                                accumulatedText += text
                                seq += 1

                                // Emit streaming delta
                                let payload = ChatEventPayload(
                                    runId: runId,
                                    sessionKey: sessionId,
                                    seq: seq,
                                    state: .delta,
                                    message: ChatEventPayload.ChatMessage(
                                        role: "assistant",
                                        content: [ChatEventPayload.ChatMessage.ContentBlock(type: "text", text: accumulatedText)],
                                        timestamp: nil,
                                    ),
                                    errorMessage: nil,
                                    usage: nil,
                                    stopReason: nil,
                                )
                                chatEventHandler?(payload)
                            } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                                currentToolInputJSON += partial
                            }
                        }

                    case "content_block_stop":
                        // If we were building a tool_use block, finalize it
                        if let toolId = currentToolId, let toolName = currentToolName {
                            toolUseBlocks.append((id: toolId, name: toolName, inputJSON: currentToolInputJSON))
                            currentToolId = nil
                            currentToolName = nil
                            currentToolInputJSON = ""
                        }

                    case "message_delta":
                        if let delta = json["delta"] as? [String: Any] {
                            stopReason = delta["stop_reason"] as? String
                        }
                        if let usageJson = json["usage"] as? [String: Any] {
                            let outputTokens = usageJson["output_tokens"] as? Int ?? 0
                            usage = AgentMessage.TokenUsage(
                                inputTokens: usage?.inputTokens ?? 0,
                                outputTokens: outputTokens,
                            )
                        }

                    case "message_start":
                        if let messageJson = json["message"] as? [String: Any],
                           let usageJson = messageJson["usage"] as? [String: Any] {
                            let inputTokens = usageJson["input_tokens"] as? Int ?? 0
                            usage = AgentMessage.TokenUsage(
                                inputTokens: inputTokens,
                                outputTokens: 0,
                            )
                        }

                    default:
                        break
                    }
                }
            }
        } catch {
            if Task.isCancelled { return .cancelled }
            return .error("Stream error: \(error.localizedDescription)")
        }

        // Build the assistant message
        var contentBlocks: [AnthropicContentBlock] = []
        if !accumulatedText.isEmpty {
            contentBlocks.append(.text(accumulatedText))
        }
        for tool in toolUseBlocks {
            let input: [String: AnthropicJSONValue] = if let inputData = tool.inputJSON.data(using: .utf8),
                                                         let decoded = try? JSONDecoder().decode([String: AnthropicJSONValue].self, from: inputData) {
                decoded
            } else {
                [:]
            }
            contentBlocks.append(.toolUse(id: tool.id, name: tool.name, input: input))
        }

        let assistantMessage = AnthropicMessage(role: "assistant", content: contentBlocks, createdAt: Date())
        return .completed(assistantMessage, usage: usage, stopReason: stopReason)
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

            // Emit tool use status to UI
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
        Logger.error("[ClaudeDirect] \(message)", category: Logger.agent)
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
}
