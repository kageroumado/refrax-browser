import Foundation

/// Mock implementation of `AgentChatClientProtocol` for previews and tests.
///
/// Configurable to simulate various states and behaviors without a real gateway connection.
///
/// ## Usage in Previews
///
/// ```swift
/// let client = MockAgentChatClient()
/// client.mockConnectionState = .connected
/// client.mockMessages = [
///     .user(text: "Hello!"),
///     .assistant(text: "Hi there! How can I help?")
/// ]
/// ```
actor MockAgentChatClient: AgentChatClientProtocol {
    // MARK: - Configuration

    /// Messages to return from `fetchChatHistory`.
    var mockMessages: [AgentMessage] = []

    /// Connection state to report.
    var mockConnectionState: AgentConnectionState = .connected

    /// Whether HTTP endpoint is available.
    var mockHTTPEndpointAvailable: Bool? = true

    /// Error for HTTP endpoint if unavailable.
    var mockHTTPEndpointError: String?

    /// Delay before returning from connect (simulates network latency).
    var connectDelay: Duration = .zero

    /// Delay before returning history (simulates loading).
    var historyDelay: Duration = .zero

    /// Error to throw from connect.
    var connectError: (any Error)?

    /// Error to throw from sendChatMessage.
    var sendError: (any Error)?

    /// Simulated response text for sent messages.
    var mockResponseText: String = "This is a mock response from the agent."

    /// Whether to simulate streaming (sends delta events).
    var simulateStreaming: Bool = true

    /// Delay between streaming delta events.
    var streamingDelay: Duration = .milliseconds(50)

    // MARK: - Protocol Properties

    var connectionState: AgentConnectionState {
        mockConnectionState
    }

    var isHTTPEndpointAvailable: Bool? {
        mockHTTPEndpointAvailable
    }

    var httpEndpointError: String? {
        mockHTTPEndpointError
    }

    // MARK: - Event Handlers

    private var chatEventHandler: (@Sendable (ChatEventPayload) -> Void)?
    private var connectionStateHandler: (@Sendable (AgentConnectionState) -> Void)?

    // MARK: - Protocol Methods

    func connect() async throws {
        if connectDelay > .zero {
            try await Task.sleep(for: connectDelay)
        }

        if let error = connectError {
            throw error
        }

        mockConnectionState = .connected
        connectionStateHandler?(mockConnectionState)
    }

    func disconnect() {
        mockConnectionState = .disconnected
        connectionStateHandler?(mockConnectionState)
    }

    func clearConversation() {
        mockMessages.removeAll()
    }

    func sendChatMessage(
        sessionKey _: String,
        message _: String,
        attachments _: [ChatSendParams.ChatAttachment]?,
    ) async throws -> String {
        if let error = sendError {
            throw error
        }

        let runId = UUID().uuidString

        // Simulate streaming response in background
        if simulateStreaming {
            Task { [weak self] in
                await self?.simulateStreamingResponse(runId: runId, sessionKey: "mock")
            }
        }

        return runId
    }

    func fetchChatHistory(sessionKey _: String, limit _: Int) async throws -> ChatHistoryResponse {
        if historyDelay > .zero {
            try await Task.sleep(for: historyDelay)
        }

        // Convert mock messages to history format
        let historyMessages = mockMessages.map { message in
            ChatHistoryResponse.HistoryMessage(
                role: message.role.rawValue,
                content: message.content.compactMap { block -> ChatHistoryResponse.HistoryMessage.ContentBlock? in
                    switch block {
                    case let .text(text):
                        return ChatHistoryResponse.HistoryMessage.ContentBlock(type: "text", text: text, source: nil)
                    case let .image(attachment):
                        let source = ChatHistoryResponse.HistoryMessage.ContentBlock.ImageSource(
                            type: "base64",
                            mediaType: attachment.mimeType,
                            data: attachment.base64Content,
                        )
                        return ChatHistoryResponse.HistoryMessage.ContentBlock(type: "image", text: nil, source: source)
                    case .toolUse, .toolResult:
                        return nil
                    }
                },
                timestamp: Int(message.timestamp.timeIntervalSince1970 * 1_000),
            )
        }

        return ChatHistoryResponse(messages: historyMessages, thinkingLevel: nil)
    }

    func abortChat(sessionKey _: String, runId: String) async throws {
        // Send aborted event
        let payload = ChatEventPayload(
            runId: runId,
            sessionKey: "mock",
            seq: 999,
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

    func checkHTTPEndpointAvailability() async {
        // No-op for mock
    }

    func enableHTTPEndpoint() async -> Bool {
        mockHTTPEndpointAvailable = true
        return true
    }

    // MARK: - Simulation Helpers

    /// Simulates a streaming response with delta events.
    private func simulateStreamingResponse(runId: String, sessionKey: String) async {
        let words = mockResponseText.split(separator: " ")
        var accumulated = ""

        for (index, word) in words.enumerated() {
            if !accumulated.isEmpty {
                accumulated += " "
            }
            accumulated += String(word)

            let payload = ChatEventPayload(
                runId: runId,
                sessionKey: sessionKey,
                seq: index + 1,
                state: .delta,
                message: ChatEventPayload.ChatMessage(
                    role: "assistant",
                    content: [ChatEventPayload.ChatMessage.ContentBlock(type: "text", text: accumulated)],
                    timestamp: nil,
                ),
                errorMessage: nil,
                usage: nil,
                stopReason: nil,
            )

            chatEventHandler?(payload)

            if streamingDelay > .zero {
                try? await Task.sleep(for: streamingDelay)
            }
        }

        // Send final event
        let finalPayload = ChatEventPayload(
            runId: runId,
            sessionKey: sessionKey,
            seq: words.count + 1,
            state: .final,
            message: ChatEventPayload.ChatMessage(
                role: "assistant",
                content: [ChatEventPayload.ChatMessage.ContentBlock(type: "text", text: accumulated)],
                timestamp: Int(Date().timeIntervalSince1970 * 1_000),
            ),
            errorMessage: nil,
            usage: ChatEventPayload.ChatUsage(input: 100, output: 50, totalTokens: 150),
            stopReason: "end_turn",
        )

        chatEventHandler?(finalPayload)
    }

    /// Manually triggers a connection state change.
    func setConnectionState(_ state: AgentConnectionState) {
        mockConnectionState = state
        connectionStateHandler?(state)
    }

    /// Manually sends a chat event (for testing).
    func sendChatEvent(_ payload: ChatEventPayload) {
        chatEventHandler?(payload)
    }
}
