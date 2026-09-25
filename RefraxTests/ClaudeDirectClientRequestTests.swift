import Foundation
import Testing

@testable import Refrax

/// Wire shape of ``ClaudeDirectClient`` requests: exact headers and the body
/// fields the Messages API accepts without beta headers.
@Suite("ClaudeDirectClient — request shape", .tags(.agentMultiProvider))
@MainActor
struct ClaudeDirectClientRequestTests {
    private func makeRequest(
        tools: [AgentToolDefinition] = AgentTools.definitions,
        messages: [AnthropicMessage] = [
            AnthropicMessage(role: "user", content: [.text("Hello")], createdAt: Date()),
        ],
    ) throws -> (URLRequest, [String: Any]) {
        let request = try ClaudeDirectClient.makeRequest(
            model: ClaudeModel.sonnet.rawValue,
            maxTokens: 8_192,
            credential: .apiKey("sk-ant-test"),
            systemPrompt: ClaudeSystemPrompt.Content(staticPart: "Static", dynamicPart: "## Current Tab"),
            tools: tools,
            messages: messages,
        )
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return (request, json)
    }

    @Test("Sends the API key, version, and JSON headers and no beta header")
    func headers() throws {
        let (request, _) = try makeRequest()

        #expect(request.url == ClaudeDirectClient.apiURL)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test("Body carries model, streaming, and a cached system prompt")
    func bodyBasics() throws {
        let (_, body) = try makeRequest()

        #expect(body["model"] as? String == "claude-sonnet-5")
        #expect(body["max_tokens"] as? Int == 8_192)
        #expect(body["stream"] as? Bool == true)

        let system = try #require(body["system"] as? [[String: Any]])
        #expect(system.count == 2)
        #expect(system[0]["text"] as? String == "Static")
        #expect((system[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect(system[1]["cache_control"] == nil)
    }

    @Test("Tools are plain custom tools: no code execution, no allowed_callers")
    func toolsShape() throws {
        let (_, body) = try makeRequest()
        let tools = try #require(body["tools"] as? [[String: Any]])

        #expect(tools.count == AgentTools.definitions.count)
        #expect(tools.allSatisfy { $0["type"] == nil })
        #expect(tools.allSatisfy { $0["allowed_callers"] == nil })
        #expect(tools.allSatisfy { $0["input_schema"] is [String: Any] })
        #expect(!tools.contains { ($0["name"] as? String) == "code_execution" })
        #expect(tools.last?["cache_control"] != nil)
        #expect(tools.dropLast().allSatisfy { $0["cache_control"] == nil })
    }

    @Test("No tools key when there are no tools")
    func noTools() throws {
        let (_, body) = try makeRequest(tools: [])
        #expect(body["tools"] == nil)
    }

    @Test("Tool use and tool result blocks serialize in Messages API shape")
    func toolMessages() throws {
        let (_, body) = try makeRequest(messages: [
            AnthropicMessage(role: "user", content: [.text("Read it")], createdAt: Date()),
            AnthropicMessage(
                role: "assistant",
                content: [.toolUse(id: "toolu_1", name: "read_page", input: ["scope": .string("text")])],
                createdAt: Date(),
            ),
            AnthropicMessage(
                role: "user",
                content: [.toolResult(toolUseId: "toolu_1", content: [.text("Page text")], isError: false)],
                createdAt: Date(),
            ),
        ])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 3)

        let toolUse = try #require((messages[1]["content"] as? [[String: Any]])?.first)
        #expect(toolUse["type"] as? String == "tool_use")
        #expect(toolUse["id"] as? String == "toolu_1")
        #expect((toolUse["input"] as? [String: Any])?["scope"] as? String == "text")

        let toolResult = try #require((messages[2]["content"] as? [[String: Any]])?.first)
        #expect(toolResult["type"] as? String == "tool_result")
        #expect(toolResult["tool_use_id"] as? String == "toolu_1")
        #expect(toolResult["content"] as? String == "Page text")
        #expect(toolResult["is_error"] == nil)
    }
}

@Suite("ClaudeModel — persisted identifiers", .tags(.agentMultiProvider))
struct ClaudeModelMigrationTests {
    @Test("Retired and empty identifiers move to the default", arguments: ["claude-opus-4-6", "claude-sonnet-4-5-20250929", "", "  "])
    func retired(identifier: String) {
        #expect(ClaudeModel.migrated(identifier) == ClaudeModel.sonnet.rawValue)
    }

    @Test("Current and custom identifiers pass through", arguments: ["claude-fable-5-1", "claude-haiku-4-5-20251001", "claude-experimental-x"])
    func passThrough(identifier: String) {
        #expect(ClaudeModel.migrated(identifier) == identifier)
    }

    @Test("Unknown persisted provider kinds decode as Claude API")
    func unknownProvider() throws {
        let decoded = try JSONDecoder().decode([AgentProviderKind].self, from: Data(#"["openClaw","claudeCode","codex"]"#.utf8))
        #expect(decoded == [.claudeAPI, .claudeCode, .codex])
    }
}
