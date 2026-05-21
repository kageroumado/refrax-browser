import Foundation

// MARK: - Connection State

/// Connection state shared across agent chat implementations.
///
/// Decoupled from any specific client so the protocol and views
/// don't depend on a concrete gateway implementation.
nonisolated enum AgentConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    var isConnected: Bool {
        self == .connected
    }

    var isTransitioning: Bool {
        switch self {
        case .connecting, .reconnecting: true
        case .disconnected, .connected: false
        }
    }

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }
}

// MARK: - Client Protocol

/// Protocol abstracting the agent chat client for testability.
///
/// Allows injecting mock implementations for previews and tests.
/// Decoupled from any specific gateway implementation.
protocol AgentChatClientProtocol: Actor {
    // MARK: - Connection State

    /// Current connection state.
    var connectionState: AgentConnectionState { get }

    /// Whether the HTTP endpoint is available for large attachments.
    var isHTTPEndpointAvailable: Bool? { get }

    /// Error message if HTTP endpoint is unavailable.
    var httpEndpointError: String? { get }

    // MARK: - Connection Management

    /// Connects to the gateway.
    func connect() async throws

    /// Disconnects from the gateway.
    func disconnect()

    // MARK: - Chat Operations

    /// Sends a chat message.
    ///
    /// - Parameters:
    ///   - sessionKey: The session key.
    ///   - message: The message text.
    ///   - attachments: Optional image attachments.
    /// - Returns: The run ID for tracking streaming events.
    func sendChatMessage(
        sessionKey: String,
        message: String,
        attachments: [ChatSendParams.ChatAttachment]?,
    ) async throws -> String

    /// Fetches chat history.
    ///
    /// - Parameters:
    ///   - sessionKey: The session key.
    ///   - limit: Maximum number of messages.
    /// - Returns: The chat history response.
    func fetchChatHistory(sessionKey: String, limit: Int) async throws -> ChatHistoryResponse

    /// Aborts an ongoing chat response.
    ///
    /// - Parameters:
    ///   - sessionKey: The session key.
    ///   - runId: The run ID to abort.
    func abortChat(sessionKey: String, runId: String) async throws

    // MARK: - Conversation Management

    /// Clears the conversation history, starting a fresh session.
    func clearConversation() async

    // MARK: - Event Handlers

    /// Sets the handler for chat events.
    func setChatEventHandler(_ handler: @escaping @Sendable (ChatEventPayload) -> Void)

    /// Sets the handler for connection state changes.
    func setConnectionStateHandler(_ handler: @escaping @Sendable (AgentConnectionState) -> Void)

    // MARK: - Tool Configuration

    /// Sets the tool definitions the client will advertise to the model.
    ///
    /// Definitions are authored in the in-app Anthropic canonical format
    /// (``AgentToolDefinition``); OpenAI-compatible clients translate them
    /// at the wire boundary via ``OpenAIToolAdapter``.
    func setToolDefinitions(_ definitions: [AgentToolDefinition])

    /// Sets the system-prompt builder, invoked on every request.
    ///
    /// Returning ``ClaudeSystemPrompt.Content`` lets Claude cache the static
    /// portion; other providers concatenate ``ClaudeSystemPrompt/Content/fullText``
    /// into a single `system` message.
    func setSystemPromptBuilder(_ builder: @escaping @MainActor @Sendable () -> ClaudeSystemPrompt.Content)

    /// Sets the tool executor used during the agentic loop.
    ///
    /// The closure receives the tool name and its decoded Anthropic-shaped
    /// JSON input, and returns a ``ToolOutput`` to be converted back to the
    /// provider's wire format.
    func setToolExecutor(_ executor: @escaping @MainActor @Sendable (String, [String: AnthropicJSONValue]) async throws -> ToolOutput)

    // MARK: - HTTP Endpoint

    /// Checks HTTP endpoint availability.
    func checkHTTPEndpointAvailability() async

    /// Enables the HTTP endpoint for large attachment support.
    ///
    /// - Returns: `true` if the endpoint was successfully enabled.
    func enableHTTPEndpoint() async -> Bool
}

// MARK: - Default Implementations

extension AgentChatClientProtocol {
    /// Fetches chat history with default limit of 200.
    func fetchChatHistory(sessionKey: String) async throws -> ChatHistoryResponse {
        try await fetchChatHistory(sessionKey: sessionKey, limit: 200)
    }

    /// Default: HTTP endpoint always available.
    var isHTTPEndpointAvailable: Bool? {
        true
    }

    /// Default: no HTTP endpoint error.
    var httpEndpointError: String? {
        nil
    }

    /// Default: no-op.
    func checkHTTPEndpointAvailability() async {}

    /// Default: always succeeds.
    func enableHTTPEndpoint() async -> Bool {
        true
    }

    /// Default: no-op. Clients that support tool calling override this.
    func setToolDefinitions(_: [AgentToolDefinition]) {}

    /// Default: no-op. Clients that support a system prompt override this.
    func setSystemPromptBuilder(_: @escaping @MainActor @Sendable () -> ClaudeSystemPrompt.Content) {}

    /// Default: no-op. Clients that execute tools override this.
    func setToolExecutor(
        _: @escaping @MainActor @Sendable (String, [String: AnthropicJSONValue]) async throws -> ToolOutput
    ) {}
}
