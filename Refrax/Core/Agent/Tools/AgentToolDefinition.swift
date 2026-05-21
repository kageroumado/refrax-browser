import Foundation

/// Definition of a tool that Claude can call during an agentic conversation.
///
/// Each tool maps to an existing `RefraxControlServer` handler, with a JSON Schema
/// input definition that matches the Anthropic API tool format.
///
/// Created on `@MainActor` (due to `JSONSerialization`), but stores only immutable
/// `Data` so is safe to read from any isolation context.
struct AgentToolDefinition: @unchecked Sendable {
    let name: String
    let description: String

    /// Pre-encoded JSON Schema for the tool's input parameters.
    let inputSchemaJSON: Data

    /// Pre-encoded API representation as JSON data.
    private let apiRepresentationJSON: Data

    @MainActor
    init(name: String, description: String, inputSchema: [String: Any], allowedCallers: [String]? = nil) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = (try? JSONSerialization.data(withJSONObject: inputSchema)) ?? Data()

        // Pre-encode the full API representation to avoid MainActor access later
        var apiDict: [String: Any] = [
            "name": name,
            "description": description,
            "input_schema": inputSchema,
        ]
        if let allowedCallers {
            apiDict["allowed_callers"] = allowedCallers
        }
        self.apiRepresentationJSON = (try? JSONSerialization.data(withJSONObject: apiDict)) ?? Data()
    }

    /// Converts to the Anthropic API tool representation (decoded from pre-encoded JSON).
    nonisolated var apiRepresentation: [String: Any] {
        (try? JSONSerialization.jsonObject(with: apiRepresentationJSON)) as? [String: Any] ?? [:]
    }
}

/// Output from executing a tool.
nonisolated struct ToolOutput: Sendable {
    nonisolated enum ContentItem: Sendable {
        case text(String)
        case image(mediaType: String, base64Data: String)

        var toToolResultContent: ToolResultContent {
            switch self {
            case let .text(text): .text(text)
            case let .image(mediaType, base64Data): .image(mediaType: mediaType, data: base64Data)
            }
        }
    }

    let content: [ContentItem]
    let isError: Bool

    init(content: [ContentItem], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    static func success(_ text: String) -> ToolOutput {
        ToolOutput(content: [.text(text)])
    }

    static func error(_ message: String) -> ToolOutput {
        ToolOutput(content: [.text(message)], isError: true)
    }

    static func withImage(text: String, mediaType: String, base64Data: String) -> ToolOutput {
        ToolOutput(content: [.text(text), .image(mediaType: mediaType, base64Data: base64Data)])
    }
}
