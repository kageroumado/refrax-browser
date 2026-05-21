import Foundation
import OSLog

/// File-based conversation persistence for Claude Direct sessions.
///
/// Stores messages in Anthropic Messages API format (JSON) so they can
/// be sent back to the API without conversion. Each session has its own file.
///
/// Storage location: `~/Library/Application Support/website.refrax.browser/agent/conversations/`
nonisolated enum ConversationStore {
    private static let directoryName = "agent/conversations"

    // MARK: - Public API

    /// Loads the conversation for a session.
    static func load(sessionId: String) -> [AnthropicMessage] {
        guard let url = fileURL(for: sessionId),
              FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([AnthropicMessage].self, from: data)
        } catch {
            Logger.error("Failed to load conversation \(sessionId): \(error)", category: Logger.agent)
            return []
        }
    }

    /// Saves the full conversation for a session.
    static func save(sessionId: String, messages: [AnthropicMessage]) {
        guard let url = fileURL(for: sessionId) else { return }

        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.error("Failed to save conversation \(sessionId): \(error)", category: Logger.agent)
        }
    }

    /// Appends a message to the conversation.
    static func append(sessionId: String, message: AnthropicMessage) {
        var messages = load(sessionId: sessionId)
        messages.append(message)
        save(sessionId: sessionId, messages: messages)
    }

    /// Clears the conversation for a session.
    static func clear(sessionId: String) {
        guard let url = fileURL(for: sessionId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Lists all stored session IDs.
    static func listSessions() -> [String] {
        guard let directory = conversationDirectory() else { return [] }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    // MARK: - File Management

    private static func conversationDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first else { return nil }

        let directory = appSupport
            .appendingPathComponent(Constants.App.bundleID)
            .appendingPathComponent(directoryName)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        }

        return directory
    }

    private static func fileURL(for sessionId: String) -> URL? {
        // Sanitize session ID for filesystem
        let sanitized = sessionId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return conversationDirectory()?.appendingPathComponent("\(sanitized).json")
    }
}

// MARK: - Anthropic Message Format

/// A message in Anthropic Messages API format.
///
/// Stored directly in this format so conversations can be sent to the API
/// without conversion overhead.
nonisolated struct AnthropicMessage: Codable, Sendable {
    let role: String
    let content: [AnthropicContentBlock]
    let createdAt: Date
}

/// Content item within a tool_result block (supports text and images).
nonisolated enum ToolResultContent: Codable, Sendable {
    case text(String)
    case image(mediaType: String, data: String)

    var isImage: Bool {
        if case .image = self { true } else { false }
    }

    var textValue: String? {
        if case let .text(value) = self { value } else { nil }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }

    private enum SourceKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = try .text(container.decode(String.self, forKey: .text))
        case "image":
            let src = try container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            self = try .image(
                mediaType: src.decode(String.self, forKey: .mediaType),
                data: src.decode(String.self, forKey: .data),
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown tool result content type: \(type)",
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(mediaType, data):
            try container.encode("image", forKey: .type)
            var src = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try src.encode("base64", forKey: .type)
            try src.encode(mediaType, forKey: .mediaType)
            try src.encode(data, forKey: .data)
        }
    }
}

/// A content block in Anthropic Messages API format.
nonisolated enum AnthropicContentBlock: Codable, Sendable {
    case text(String)
    case image(mediaType: String, data: String)
    case toolUse(id: String, name: String, input: [String: AnthropicJSONValue])
    case toolResult(toolUseId: String, content: [ToolResultContent], isError: Bool)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    private enum SourceKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let sourceContainer = try container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            let mediaType = try sourceContainer.decode(String.self, forKey: .mediaType)
            let data = try sourceContainer.decode(String.self, forKey: .data)
            self = .image(mediaType: mediaType, data: data)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode([String: AnthropicJSONValue].self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            // Content can be a string (legacy/simple) or array of content items
            let content: [ToolResultContent] = if let stringContent = try? container.decode(String.self, forKey: .content) {
                [.text(stringContent)]
            } else if let arrayContent = try? container.decode([ToolResultContent].self, forKey: .content) {
                arrayContent
            } else {
                []
            }
            self = .toolResult(toolUseId: toolUseId, content: content, isError: isError)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content block type: \(type)",
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(mediaType, data):
            try container.encode("image", forKey: .type)
            var sourceContainer = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try sourceContainer.encode("base64", forKey: .type)
            try sourceContainer.encode(mediaType, forKey: .mediaType)
            try sourceContainer.encode(data, forKey: .data)
        case let .toolUse(id, name, input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .toolResult(toolUseId, content, isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        }
    }
}

// MARK: - JSON Value Type

/// Type-safe JSON value for tool inputs.
nonisolated enum AnthropicJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([AnthropicJSONValue])
    case object([String: AnthropicJSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnthropicJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnthropicJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnthropicJSONValue",
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// Converts to a Swift dictionary representation for handler calls.
    var swiftValue: Any {
        switch self {
        case let .string(v): v
        case let .number(v): v
        case let .bool(v): v
        case .null: NSNull()
        case let .array(v): v.map(\.swiftValue)
        case let .object(v): v.mapValues(\.swiftValue)
        }
    }
}
