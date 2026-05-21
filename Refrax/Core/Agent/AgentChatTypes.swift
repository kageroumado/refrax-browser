import Foundation

// MARK: - Chat Send Parameters

/// Parameters for sending a chat message.
///
/// Clients translate these into their transport-specific format.
nonisolated struct ChatSendParams: Encodable, Sendable {
    let sessionKey: String
    let message: String
    let idempotencyKey: String
    let attachments: [ChatAttachment]?
    let thinking: String?
    let timeoutMs: Int?

    /// A file attachment included with a chat message.
    nonisolated struct ChatAttachment: Encodable, Sendable {
        /// The attachment type (e.g., "image").
        let type: String
        /// The MIME type (e.g., "image/png").
        let mimeType: String
        /// An optional display file name.
        let fileName: String?
        /// The base64-encoded file content.
        let content: String
    }
}

// MARK: - Chat Event State

/// State of a chat event.
nonisolated enum ChatEventState: String, Codable, Sendable {
    case delta
    case final
    case aborted
    case error

    /// Whether this state represents a terminal event (stream ended).
    var isTerminal: Bool {
        switch self {
        case .final, .error, .aborted: true
        case .delta: false
        }
    }
}

// MARK: - Chat Event Payload

/// Payload for chat events.
nonisolated struct ChatEventPayload: Decodable, Sendable {
    let runId: String
    let sessionKey: String
    let seq: Int
    let state: ChatEventState
    let message: ChatMessage?
    let errorMessage: String?
    let usage: ChatUsage?
    let stopReason: String?

    nonisolated struct ChatMessage: Decodable, Sendable {
        let role: String
        let content: [ContentBlock]
        let timestamp: Int?

        nonisolated struct ContentBlock: Decodable, Sendable {
            let type: String
            let text: String?

            /// Tool use ID (when `type == "tool_use"`).
            let id: String?
            /// Tool name (when `type == "tool_use"`).
            let name: String?
            /// Tool use ID that this result responds to (when `type == "tool_result"`).
            let toolUseId: String?
            /// Whether the tool result is an error (when `type == "tool_result"`).
            let isError: Bool?

            init(type: String, text: String?, id: String? = nil, name: String? = nil, toolUseId: String? = nil, isError: Bool? = nil) {
                self.type = type
                self.text = text
                self.id = id
                self.name = name
                self.toolUseId = toolUseId
                self.isError = isError
            }
        }
    }

    nonisolated struct ChatUsage: Decodable, Sendable {
        let input: Int?
        let output: Int?
        let totalTokens: Int?
    }
}

// MARK: - Chat Send Response

/// Response payload for chat.send.
nonisolated struct ChatSendResponse: Decodable, Sendable {
    let runId: String
    let status: String
}

// MARK: - Chat History Response

/// Response payload for chat.history.
nonisolated struct ChatHistoryResponse: Decodable, Sendable {
    let messages: [HistoryMessage]
    let thinkingLevel: String?

    nonisolated struct HistoryMessage: Decodable, Sendable {
        let role: String
        let content: [ContentBlock]
        let timestamp: Int?

        nonisolated struct ContentBlock: Decodable, Sendable {
            let type: String
            let text: String?
            /// Image source for image content blocks (Anthropic API format).
            let source: ImageSource?

            /// Image source in the Anthropic API's base64 format.
            nonisolated struct ImageSource: Decodable, Sendable {
                let type: String // "base64"
                let mediaType: String // "image/png", "image/jpeg", etc.
                let data: String // base64-encoded image data

                private enum CodingKeys: String, CodingKey {
                    case type
                    case mediaType = "media_type"
                    case data
                }
            }
        }
    }
}
