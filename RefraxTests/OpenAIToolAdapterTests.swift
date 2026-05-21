import Foundation
import Testing

@testable import Refrax

// MARK: - Tags

extension Tag {
    /// Tests for multi-provider agent infrastructure.
    @Tag static var agentMultiProvider: Self
}

// MARK: - Tool Definition Translation

@Suite("OpenAIToolAdapter — tool definitions", .tags(.agentMultiProvider))
@MainActor
struct OpenAIToolAdapterToolDefinitionTests {
    @Test("Translates Anthropic-shaped definition to OpenAI function shape")
    func translatesDefinition() throws {
        let tool = AgentToolDefinition(
            name: "navigate",
            description: "Navigate the current tab to a URL.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "url": [
                        "type": "string",
                        "description": "The URL to navigate to",
                    ],
                ],
                "required": ["url"],
            ],
        )

        let wire = OpenAIToolAdapter.toolsJSON(from: [tool])

        #expect(wire.count == 1)
        let entry = try #require(wire.first)
        #expect(entry["type"] as? String == "function")

        let function = try #require(entry["function"] as? [String: Any])
        #expect(function["name"] as? String == "navigate")
        #expect(function["description"] as? String == "Navigate the current tab to a URL.")

        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect((parameters["required"] as? [String])?.first == "url")
    }

    @Test("Drops Anthropic-only allowedCallers field")
    func dropsAllowedCallers() throws {
        let tool = AgentToolDefinition(
            name: "execute_program",
            description: "Run a program.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            allowedCallers: ["code_execution_20250825"],
        )

        let wire = OpenAIToolAdapter.toolsJSON(from: [tool])
        let entry = try #require(wire.first)
        let function = try #require(entry["function"] as? [String: Any])

        // The allowed_callers field is Anthropic-specific — must not appear
        // inside or outside the function object.
        #expect(function["allowed_callers"] == nil)
        #expect(function["allowedCallers"] == nil)
        #expect(entry["allowed_callers"] == nil)
    }

    @Test("Default parameters for tools with no schema")
    func defaultParameters() throws {
        // Construct a definition whose `apiRepresentation` might be missing input_schema.
        let tool = AgentToolDefinition(
            name: "go_back",
            description: "Navigate back.",
            inputSchema: ["type": "object", "properties": [String: Any](), "required": [] as [String]],
        )
        let wire = OpenAIToolAdapter.toolsJSON(from: [tool])
        let function = try #require(wire.first?["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
    }
}

// MARK: - Message Translation

@Suite("OpenAIToolAdapter — message encoding", .tags(.agentMultiProvider))
struct OpenAIToolAdapterMessageTests {
    @Test("User text-only message becomes plain string content")
    func userTextOnly() throws {
        let msg = AnthropicMessage(
            role: "user",
            content: [.text("Hello there")],
            createdAt: Date(),
        )
        let encoded = OpenAIToolAdapter.encodeMessages([msg])
        #expect(encoded.count == 1)
        #expect(encoded[0]["role"] as? String == "user")
        #expect(encoded[0]["content"] as? String == "Hello there")
    }

    @Test("User message with image becomes array content with image_url")
    func userWithImage() throws {
        let msg = AnthropicMessage(
            role: "user",
            content: [
                .image(mediaType: "image/png", data: "QUJD"),
                .text("Describe this"),
            ],
            createdAt: Date(),
        )
        let encoded = OpenAIToolAdapter.encodeMessages([msg])
        #expect(encoded.count == 1)
        let parts = try #require(encoded[0]["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts.contains { $0["type"] as? String == "text" })
        let imagePart = try #require(parts.first { $0["type"] as? String == "image_url" })
        let urlContainer = try #require(imagePart["image_url"] as? [String: Any])
        #expect(urlContainer["url"] as? String == "data:image/png;base64,QUJD")
    }

    @Test("Assistant tool_use becomes tool_calls array")
    func assistantToolUse() throws {
        let msg = AnthropicMessage(
            role: "assistant",
            content: [
                .text("Looking up the weather"),
                .toolUse(id: "call_abc", name: "read_page", input: [
                    "scope": .string("viewport"),
                    "limit": .number(10),
                    "fast": .bool(true),
                ]),
            ],
            createdAt: Date(),
        )
        let encoded = OpenAIToolAdapter.encodeMessages([msg])
        #expect(encoded.count == 1)
        #expect(encoded[0]["role"] as? String == "assistant")
        #expect(encoded[0]["content"] as? String == "Looking up the weather")

        let toolCalls = try #require(encoded[0]["tool_calls"] as? [[String: Any]])
        #expect(toolCalls.count == 1)
        let call = toolCalls[0]
        #expect(call["id"] as? String == "call_abc")
        #expect(call["type"] as? String == "function")
        let function = try #require(call["function"] as? [String: Any])
        #expect(function["name"] as? String == "read_page")

        let argsJSON = try #require(function["arguments"] as? String)
        let args = try JSONSerialization.jsonObject(with: Data(argsJSON.utf8)) as? [String: Any]
        #expect(args?["scope"] as? String == "viewport")
        #expect(args?["limit"] as? Double == 10)
        #expect(args?["fast"] as? Bool == true)
    }

    @Test("User tool_result becomes role:tool message")
    func toolResultBecomesToolRole() throws {
        let msg = AnthropicMessage(
            role: "user",
            content: [
                .toolResult(
                    toolUseId: "call_abc",
                    content: [.text("Page contents here")],
                    isError: false,
                ),
            ],
            createdAt: Date(),
        )
        let encoded = OpenAIToolAdapter.encodeMessages([msg])
        #expect(encoded.count == 1)
        #expect(encoded[0]["role"] as? String == "tool")
        #expect(encoded[0]["tool_call_id"] as? String == "call_abc")
        #expect(encoded[0]["content"] as? String == "Page contents here")
    }

    @Test("Mixed user message + tool result produces two OpenAI messages")
    func mixedUserAndToolResult() throws {
        let msg = AnthropicMessage(
            role: "user",
            content: [
                .toolResult(toolUseId: "t1", content: [.text("result")], isError: false),
                .text("Please continue"),
            ],
            createdAt: Date(),
        )
        let encoded = OpenAIToolAdapter.encodeMessages([msg])
        // Order: user message first, tool result second (tool results are emitted after the user text).
        #expect(encoded.count == 2)
        let roles = encoded.compactMap { $0["role"] as? String }
        #expect(roles.contains("user"))
        #expect(roles.contains("tool"))
    }

    @Test("Round-trip: arguments string decodes back to canonical input")
    func argumentsRoundTrip() throws {
        let input: [String: AnthropicJSONValue] = [
            "text": .string("hello"),
            "count": .number(42),
            "flags": .array([.bool(true), .bool(false)]),
            "nested": .object(["key": .string("value")]),
        ]
        let jsonString = OpenAIToolAdapter.encodeArgumentsJSON(input)
        let decoded = OpenAIToolAdapter.decodeArgumentsJSON(jsonString)

        #expect(decoded["text"] == .string("hello"))
        #expect(decoded["count"] == .number(42))
        #expect(decoded["flags"] == .array([.bool(true), .bool(false)]))
        #expect(decoded["nested"] == .object(["key": .string("value")]))
    }

    @Test("Nested tool input with arrays round-trips")
    func nestedArgumentsRoundTrip() throws {
        let input: [String: AnthropicJSONValue] = [
            "fields": .array([
                .object(["ref": .string("e1"), "value": .string("john")]),
                .object(["ref": .string("e2"), "value": .string("doe")]),
            ]),
        ]
        let jsonString = OpenAIToolAdapter.encodeArgumentsJSON(input)
        let decoded = OpenAIToolAdapter.decodeArgumentsJSON(jsonString)

        if case let .array(arr) = decoded["fields"] {
            #expect(arr.count == 2)
            if case let .object(first) = arr[0] {
                #expect(first["ref"] == .string("e1"))
            } else {
                Issue.record("expected object")
            }
        } else {
            Issue.record("expected array")
        }
    }
}

// MARK: - Model List Parsing

@Suite("AgentModelLoader — response parsing", .tags(.agentMultiProvider))
@MainActor
struct AgentModelLoaderParseTests {
    @Test("OpenRouter response yields rich entries")
    func parsesOpenRouterResponse() throws {
        let json = """
        {
          "data": [
            {
              "id": "anthropic/claude-opus-4.6",
              "name": "Claude Opus 4.6",
              "context_length": 200000,
              "pricing": {"prompt": "0.000015", "completion": "0.000075"},
              "supported_parameters": ["tools", "temperature"]
            },
            {
              "id": "meta/llama-no-tools",
              "supported_parameters": ["temperature"]
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let entries = AgentModelLoader.parseModelList(data: data, provider: .openRouter)

        // The non-tool-supporting entry should be filtered out.
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.id == "anthropic/claude-opus-4.6")
        #expect(entry.displayName == "Claude Opus 4.6")
        #expect(entry.contextLength == 200_000)
        #expect(entry.pricePromptPerMillion == 15.0)
        #expect(entry.priceCompletionPerMillion == 75.0)
    }

    @Test("Ollama-style minimal response yields plain entries")
    func parsesMinimalResponse() throws {
        let json = """
        {
          "data": [
            {"id": "llama3.1:latest"},
            {"id": "qwen2.5-coder:7b"}
          ]
        }
        """
        let data = Data(json.utf8)
        let entries = AgentModelLoader.parseModelList(data: data, provider: .custom)
        #expect(entries.count == 2)
        #expect(entries.map(\.id).contains("llama3.1:latest"))
        #expect(entries.map(\.id).contains("qwen2.5-coder:7b"))
    }
}
