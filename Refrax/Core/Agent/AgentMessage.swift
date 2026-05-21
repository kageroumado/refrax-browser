import Foundation

/// A message in an agent chat conversation.
///
/// Messages are transient UI state, not persisted to SwiftData.
/// They support text content and optional attachments (images).
nonisolated struct AgentMessage: Identifiable, Equatable, Sendable {
    /// Unique identifier for this message.
    let id: UUID

    /// The role of the message author.
    let role: AgentMessageRole

    /// Content blocks in this message.
    var content: [ContentBlock]

    /// Timestamp when this message was created or received.
    let timestamp: Date

    /// Run ID for tracking streaming responses (assistant messages only).
    let runId: String?

    /// Stop reason for completed assistant messages.
    var stopReason: String?

    /// Token usage for this message (assistant messages only).
    var usage: TokenUsage?

    /// Whether this message failed to send.
    var sendFailed: Bool = false

    /// Error message if send failed.
    var sendError: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        role: AgentMessageRole,
        content: [ContentBlock],
        timestamp: Date = Date(),
        runId: String? = nil,
        stopReason: String? = nil,
        usage: TokenUsage? = nil,
        sendFailed: Bool = false,
        sendError: String? = nil,
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.runId = runId
        self.stopReason = stopReason
        self.usage = usage
        self.sendFailed = sendFailed
        self.sendError = sendError
    }

    /// Creates a user message with text content.
    static func user(text: String, attachments: [ImageAttachment] = []) -> AgentMessage {
        var content: [ContentBlock] = attachments.map { .image($0) }
        content.append(.text(text))
        return AgentMessage(role: .user, content: content)
    }

    /// Creates an assistant message with text content.
    static func assistant(text: String, runId: String? = nil) -> AgentMessage {
        AgentMessage(
            role: .assistant,
            content: [.text(text)],
            runId: runId,
        )
    }

    /// Creates an empty assistant message for streaming.
    static func streamingAssistant(runId: String) -> AgentMessage {
        AgentMessage(
            role: .assistant,
            content: [],
            runId: runId,
        )
    }

    // MARK: - Computed Properties

    /// The combined text content of this message.
    var textContent: String {
        content.compactMap(\.textValue).joined()
    }

    /// Image attachments in this message.
    var imageAttachments: [ImageAttachment] {
        content.compactMap(\.imageValue)
    }

    /// Whether this message is empty (no content).
    var isEmpty: Bool {
        content.isEmpty || (content.count == 1 && textContent.isEmpty && imageAttachments.isEmpty && toolUseBlocks.isEmpty)
    }

    /// Tool use blocks in this message.
    var toolUseBlocks: [ToolUseBlock] {
        content.compactMap(\.toolUseValue)
    }

    /// Tool result blocks in this message.
    var toolResultBlocks: [ToolResultBlock] {
        content.compactMap(\.toolResultValue)
    }

    /// Whether this message contains any tool interactions.
    var hasToolContent: Bool {
        content.contains { block in
            if case .toolUse = block { return true }
            if case .toolResult = block { return true }
            return false
        }
    }

    // MARK: - Content Modification

    /// Appends text to this message (for streaming).
    mutating func appendText(_ text: String) {
        if let lastIndex = content.lastIndex(where: \.isText),
           case let .text(existing) = content[lastIndex] {
            content[lastIndex] = .text(existing + text)
        } else {
            content.append(.text(text))
        }
    }

    // MARK: - Equatable

    static func == (lhs: AgentMessage, rhs: AgentMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
            && lhs.content == rhs.content
            && lhs.timestamp == rhs.timestamp
            && lhs.runId == rhs.runId
            && lhs.stopReason == rhs.stopReason
            && lhs.sendFailed == rhs.sendFailed
    }
}

// MARK: - Content Block

extension AgentMessage {
    /// A block of content within a message.
    nonisolated enum ContentBlock: Equatable, Sendable {
        case text(String)
        case image(ImageAttachment)
        case toolUse(ToolUseBlock)
        case toolResult(ToolResultBlock)

        var isText: Bool {
            if case .text = self { true } else { false }
        }

        var textValue: String? {
            if case let .text(value) = self { value } else { nil }
        }

        var imageValue: ImageAttachment? {
            if case let .image(value) = self { value } else { nil }
        }

        var toolUseValue: ToolUseBlock? {
            if case let .toolUse(value) = self { value } else { nil }
        }

        var toolResultValue: ToolResultBlock? {
            if case let .toolResult(value) = self { value } else { nil }
        }
    }

    /// A tool use request from the assistant.
    nonisolated struct ToolUseBlock: Equatable, Sendable {
        let id: String
        let name: String
        let displayName: String

        init(id: String, name: String) {
            self.id = id
            self.name = name
            self.displayName = Self.humanReadableName(name)
        }

        private static func humanReadableName(_ name: String) -> String {
            switch name {
            case "read_page": "Read page"
            case "screenshot": "Screenshot"
            case "navigate": "Navigate"
            case "click": "Click"
            case "type": "Type text"
            case "scroll": "Scroll"
            case "form_input": "Fill form"
            case "tabs_list": "List tabs"
            case "execute_javascript": "Run JavaScript"
            default: name.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    /// A tool execution result.
    nonisolated struct ToolResultBlock: Equatable, Sendable {
        let toolUseId: String
        let content: String
        let isError: Bool
    }
}

// MARK: - Image Attachment

extension AgentMessage {
    /// An image attachment in a message.
    ///
    /// Supports two modes:
    /// - **Loaded**: Data is available immediately (user-added attachments)
    /// - **Lazy**: Base64 string from history, decoded on demand when visible
    nonisolated struct ImageAttachment: Identifiable, Equatable, Sendable {
        let id: UUID
        let mimeType: String
        let fileName: String?

        /// The image content - either decoded data or pending base64 string.
        private let content: ImageContent

        // MARK: - Initialization

        /// Creates an attachment with already-decoded image data.
        init(id: UUID = UUID(), data: Data, mimeType: String, fileName: String? = nil) {
            self.id = id
            self.mimeType = mimeType
            self.fileName = fileName
            self.content = .loaded(data)
        }

        /// Creates a lazy attachment from base64 string (for history loading).
        init(id: UUID = UUID(), base64: String, mimeType: String, fileName: String? = nil) {
            self.id = id
            self.mimeType = mimeType
            self.fileName = fileName
            self.content = .lazy(base64)
        }

        // MARK: - Content Access

        /// Whether the image data is already decoded.
        var isLoaded: Bool {
            if case .loaded = content { true } else { false }
        }

        /// The decoded image data, or nil if not yet loaded.
        var data: Data? {
            switch content {
            case let .loaded(data): data
            case .lazy: nil
            }
        }

        /// The base64 string for lazy loading, or nil if already loaded.
        var base64String: String? {
            switch content {
            case .loaded: nil
            case let .lazy(base64): base64
            }
        }

        /// Decodes the base64 content and returns a new attachment with loaded data.
        /// Returns nil if decoding fails or content is already loaded.
        func decoded() -> ImageAttachment? {
            guard case let .lazy(base64) = content,
                  let data = Data(base64Encoded: base64) else {
                return nil
            }
            return ImageAttachment(id: id, data: data, mimeType: mimeType, fileName: fileName)
        }

        /// Encoded base64 content for sending to gateway.
        var base64Content: String {
            switch content {
            case let .loaded(data): data.base64EncodedString()
            case let .lazy(base64): base64
            }
        }

        /// Estimated size in bytes.
        var sizeBytes: Int {
            switch content {
            case let .loaded(data): data.count
            case let .lazy(base64): base64.count * 3 / 4 // Approximate decoded size
            }
        }
    }

    /// Internal content representation for lazy loading.
    private nonisolated enum ImageContent: Equatable, Sendable {
        case loaded(Data)
        case lazy(String) // base64 string
    }
}

// MARK: - Token Usage

extension AgentMessage {
    /// Token usage statistics for an assistant response.
    nonisolated struct TokenUsage: Equatable, Sendable {
        let inputTokens: Int
        let outputTokens: Int

        var totalTokens: Int {
            inputTokens + outputTokens
        }
    }
}

// MARK: - Message Role

/// The role of a message author.
nonisolated enum AgentMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - Conversion from Protocol Types

extension AgentMessage {
    /// Creates an AgentMessage from a chat history message.
    ///
    /// Images are parsed as lazy attachments - the base64 data is stored but not decoded
    /// until the message view becomes visible. This prevents memory spikes when loading
    /// history with many images.
    nonisolated init(from historyMessage: ChatHistoryResponse.HistoryMessage) {
        let role: AgentMessageRole = switch historyMessage.role {
        case "user": .user
        case "assistant": .assistant
        case "system": .system
        default: .assistant
        }

        let content: [ContentBlock] = historyMessage.content.compactMap { block in
            switch block.type {
            case "text":
                if let text = block.text {
                    return .text(text)
                }
            case "image":
                // Parse image source (Anthropic API format)
                if let source = block.source, source.type == "base64" {
                    let attachment = ImageAttachment(
                        base64: source.data,
                        mimeType: source.mediaType,
                        fileName: nil,
                    )
                    return .image(attachment)
                }
            default:
                break
            }
            return nil
        }

        let timestamp = if let ts = historyMessage.timestamp {
            Date(timeIntervalSince1970: TimeInterval(ts) / 1_000.0)
        } else {
            Date()
        }

        self.init(
            role: role,
            content: content,
            timestamp: timestamp,
        )
    }

    /// Updates this message from a chat event payload.
    ///
    /// Text blocks replace existing text (each delta contains the full accumulated text).
    /// Tool blocks are appended to preserve existing content during the agentic loop.
    mutating func update(from payload: ChatEventPayload) {
        if let message = payload.message {
            var newTextBlocks: [ContentBlock] = []
            var newToolBlocks: [ContentBlock] = []

            for block in message.content {
                switch block.type {
                case "text":
                    if let text = block.text {
                        newTextBlocks.append(.text(text))
                    }
                case "tool_use":
                    if let id = block.id, let name = block.name {
                        newToolBlocks.append(.toolUse(ToolUseBlock(id: id, name: name)))
                    }
                case "tool_result":
                    if let toolUseId = block.toolUseId {
                        newToolBlocks.append(.toolResult(ToolResultBlock(
                            toolUseId: toolUseId,
                            content: block.text ?? "",
                            isError: block.isError ?? false,
                        )))
                    }
                default:
                    break
                }
            }

            if !newToolBlocks.isEmpty {
                // Tool blocks: append to existing content (don't replace)
                // Deduplicate by checking existing tool IDs
                let existingToolUseIds = Set(content.compactMap(\.toolUseValue).map(\.id))
                let existingToolResultIds = Set(content.compactMap(\.toolResultValue).map(\.toolUseId))
                for block in newToolBlocks {
                    switch block {
                    case let .toolUse(toolUse) where existingToolUseIds.contains(toolUse.id):
                        continue
                    case let .toolResult(toolResult) where existingToolResultIds.contains(toolResult.toolUseId):
                        continue
                    default:
                        content.append(block)
                    }
                }
            }

            if !newTextBlocks.isEmpty {
                // Text blocks: replace existing text content (streaming accumulation)
                content.removeAll(where: \.isText)
                content.append(contentsOf: newTextBlocks)
            }
        }

        if let reason = payload.stopReason {
            stopReason = reason
        }

        if let usage = payload.usage {
            self.usage = TokenUsage(
                inputTokens: usage.input ?? 0,
                outputTokens: usage.output ?? 0,
            )
        }
    }
}
