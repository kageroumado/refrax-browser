import Foundation

/// Translates between the in-app **Anthropic canonical** tool format and the
/// **OpenAI Chat Completions** wire format.
///
/// Refrax authors tool definitions, results, and message blocks in Anthropic
/// shape (``AgentToolDefinition``, ``AnthropicContentBlock``); when talking
/// to OpenAI-compatible endpoints we convert at the wire boundary so the
/// rest of the app doesn't need to know which provider is active.
///
/// ## Translation table
///
/// | Anthropic (canonical) | OpenAI wire |
/// |---|---|
/// | `{name, description, input_schema}` | `{type: "function", function: {name, description, parameters}}` |
/// | `{type: "tool_use", id, name, input}` (assistant) | `tool_calls: [{id, type: "function", function: {name, arguments: JSON string}}]` |
/// | `{type: "tool_result", tool_use_id, content}` (user) | `{role: "tool", tool_call_id, content: string}` |
/// | `{type: "image", source: {type: "base64", media_type, data}}` | `{type: "image_url", image_url: {url: "data:<media>;base64,<data>"}}` |
nonisolated enum OpenAIToolAdapter {
    // MARK: - Tool Definitions

    /// Converts Refrax's Anthropic-shaped tool definitions into OpenAI
    /// `{type: "function", function: ...}` dictionaries.
    ///
    /// Drops Anthropic-only extensions like `allowed_callers` — OpenAI
    /// rejects unknown top-level keys on the function object.
    static func toolsJSON(from definitions: [AgentToolDefinition]) -> [[String: Any]] {
        definitions.map { definition in
            let anthropic = definition.apiRepresentation
            var functionObject: [String: Any] = [
                "name": anthropic["name"] as? String ?? definition.name,
                "description": anthropic["description"] as? String ?? definition.description,
            ]
            if let schema = anthropic["input_schema"] as? [String: Any] {
                functionObject["parameters"] = schema
            } else {
                functionObject["parameters"] = ["type": "object", "properties": [String: Any]()]
            }
            return [
                "type": "function",
                "function": functionObject,
            ]
        }
    }

    // MARK: - Messages (canonical → OpenAI)

    /// Encodes a canonical Anthropic-shaped message into the OpenAI
    /// Chat Completions `messages[]` format.
    ///
    /// One canonical message may expand into multiple OpenAI messages: a
    /// user message containing `tool_result` blocks becomes one `role: "tool"`
    /// message per result.
    static func encodeMessages(_ messages: [AnthropicMessage]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for message in messages {
            switch message.role {
            case "user":
                encodeUserMessage(message, into: &out)
            case "assistant":
                out.append(encodeAssistantMessage(message))
            case "system":
                if let text = plainText(from: message.content) {
                    out.append(["role": "system", "content": text])
                }
            default:
                break
            }
        }
        return out
    }

    private static func encodeUserMessage(_ message: AnthropicMessage, into out: inout [[String: Any]]) {
        // Split tool_result blocks (become separate role:"tool" messages) from
        // normal content blocks (collapse into one role:"user" message).
        var userParts: [[String: Any]] = []
        var userText = ""
        var toolResultMessages: [[String: Any]] = []

        for block in message.content {
            switch block {
            case let .text(text):
                userText += text
                userParts.append(["type": "text", "text": text])
            case let .image(mediaType, data):
                userParts.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(mediaType);base64,\(data)",
                    ],
                ])
            case .toolUse:
                continue // Tool calls only appear on assistant messages.
            case let .toolResult(toolUseId, content, _):
                toolResultMessages.append([
                    "role": "tool",
                    "tool_call_id": toolUseId,
                    "content": toolResultString(from: content),
                ])
            }
        }

        if !userParts.isEmpty {
            // Always emit array form when there are multiple parts or any image;
            // otherwise prefer a plain string for maximum server compatibility.
            let hasImage = userParts.contains { ($0["type"] as? String) == "image_url" }
            if hasImage || userParts.count > 1 {
                out.append(["role": "user", "content": userParts])
            } else {
                out.append(["role": "user", "content": userText])
            }
        }

        out.append(contentsOf: toolResultMessages)
    }

    private static func encodeAssistantMessage(_ message: AnthropicMessage) -> [String: Any] {
        var textBuffer = ""
        var toolCalls: [[String: Any]] = []

        for block in message.content {
            switch block {
            case let .text(text):
                textBuffer += text
            case let .toolUse(id, name, input):
                let arguments = encodeArgumentsJSON(input)
                toolCalls.append([
                    "id": id,
                    "type": "function",
                    "function": [
                        "name": name,
                        "arguments": arguments,
                    ],
                ])
            case .image, .toolResult:
                continue // Not valid on assistant messages.
            }
        }

        var out: [String: Any] = ["role": "assistant"]
        if !textBuffer.isEmpty {
            out["content"] = textBuffer
        } else if toolCalls.isEmpty {
            // Edge case: assistant with no content at all. OpenAI requires
            // at least one of content/tool_calls to be non-null.
            out["content"] = ""
        }
        if !toolCalls.isEmpty {
            out["tool_calls"] = toolCalls
        }
        return out
    }

    /// Serializes a tool input dictionary to the compact JSON string that
    /// OpenAI expects in `tool_call.function.arguments`.
    static func encodeArgumentsJSON(_ input: [String: AnthropicJSONValue]) -> String {
        let swiftDict = input.mapValues(\.swiftValue)
        guard JSONSerialization.isValidJSONObject(swiftDict),
              let data = try? JSONSerialization.data(withJSONObject: swiftDict, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }

    /// Parses an OpenAI `tool_call.function.arguments` JSON string back into
    /// the Anthropic-canonical typed dictionary.
    static func decodeArgumentsJSON(_ raw: String) -> [String: AnthropicJSONValue] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: AnthropicJSONValue].self, from: data)
        else { return [:] }
        return decoded
    }

    // MARK: - Helpers

    private static func plainText(from blocks: [AnthropicContentBlock]) -> String? {
        let text = blocks.compactMap { block -> String? in
            if case let .text(value) = block { return value }
            return nil
        }.joined()
        return text.isEmpty ? nil : text
    }

    /// Flattens a `tool_result` content array into the single string that
    /// OpenAI's `role: "tool"` message expects. Text items are concatenated;
    /// images become a `data:` URL wrapped in a short marker so the model
    /// still sees them — OpenAI doesn't support image content on tool
    /// messages, so this is the best-effort fallback.
    private static func toolResultString(from content: [ToolResultContent]) -> String {
        var pieces: [String] = []
        for item in content {
            switch item {
            case let .text(text):
                pieces.append(text)
            case let .image(mediaType, data):
                pieces.append("[image \(mediaType), base64 length \(data.count)]")
            }
        }
        return pieces.joined(separator: "\n")
    }
}
