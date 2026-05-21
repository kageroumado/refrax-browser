import Foundation
import Testing

@testable import Refrax

// MARK: - SSE Decoder Tests

@Suite("OpenAIStreamDecoder — SSE parsing", .tags(.agentMultiProvider))
struct OpenAIStreamDecoderTests {
    /// Feeds a canned sequence of `data: {...}` SSE lines into the decoder,
    /// mirroring what ``OpenAICompatibleClient`` does with the real network
    /// stream.
    private func feed(_ lines: [String], into decoder: OpenAIStreamDecoder) -> [OpenAIStreamDecoder.Event] {
        var events: [OpenAIStreamDecoder.Event] = []
        for line in lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            events.append(contentsOf: decoder.consume(chunk: json))
        }
        return events
    }

    @Test("Streams text deltas and reports accumulated content each time")
    func streamsTextDeltas() throws {
        let decoder = OpenAIStreamDecoder()
        let events = feed([
            """
            data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{"content":", "},"finish_reason":null}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{"content":"world"},"finish_reason":null}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":3}}
            """,
            "data: [DONE]",
        ], into: decoder)

        let textEvents = events.compactMap { event -> String? in
            if case let .textDelta(accumulated) = event { return accumulated }
            return nil
        }
        #expect(textEvents == ["Hello", "Hello, ", "Hello, world"])

        let result = decoder.finalize()
        #expect(result.text == "Hello, world")
        #expect(result.toolCalls.isEmpty)
        #expect(result.stopReason == "stop")
        #expect(result.usage?.inputTokens == 12)
        #expect(result.usage?.outputTokens == 3)
    }

    @Test("Accumulates tool-call fragments keyed by index")
    func accumulatesToolCallFragments() throws {
        let decoder = OpenAIStreamDecoder()
        feed([
            """
            data: {"choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_42","type":"function","function":{"name":"read_page","arguments":""}}]}}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"scope\\":"}}]}}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"viewport\\"}"}}]}}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
            """,
            "data: [DONE]",
        ], into: decoder)

        let result = decoder.finalize()
        #expect(result.stopReason == "tool_use") // Normalized from tool_calls.
        #expect(result.toolCalls.count == 1)

        let call = try #require(result.toolCalls.first)
        #expect(call.id == "call_42")
        #expect(call.name == "read_page")

        let args = OpenAIToolAdapter.decodeArgumentsJSON(call.argumentsJSON)
        #expect(args["scope"] == .string("viewport"))
    }

    @Test("Parallel tool calls are keyed by index independently")
    func parallelToolCalls() throws {
        let decoder = OpenAIStreamDecoder()
        feed([
            """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"read_page","arguments":"{}"}}]}}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_b","type":"function","function":{"name":"screenshot","arguments":"{}"}}]}}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
            """,
            "data: [DONE]",
        ], into: decoder)

        let result = decoder.finalize()
        #expect(result.toolCalls.count == 2)
        #expect(result.toolCalls.map(\.id) == ["call_a", "call_b"])
        #expect(result.toolCalls.map(\.name) == ["read_page", "screenshot"])
    }

    @Test("Usage-only final chunk is still recognized")
    func finalUsageOnlyChunk() throws {
        let decoder = OpenAIStreamDecoder()
        feed([
            """
            data: {"choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
            """,
            """
            data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":1,"total_tokens":6}}
            """,
            "data: [DONE]",
        ], into: decoder)

        let result = decoder.finalize()
        #expect(result.text == "Hi")
        #expect(result.usage?.inputTokens == 5)
        #expect(result.usage?.outputTokens == 1)
        #expect(result.stopReason == "stop")
    }

    @Test("Empty-content deltas don't fire spurious textDelta events")
    func emptyContentDeltasNoisy() throws {
        let decoder = OpenAIStreamDecoder()
        let events = feed([
            """
            data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{"content":"Ok"},"finish_reason":null}]}
            """,
            """
            data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
            """,
            "data: [DONE]",
        ], into: decoder)

        let textEvents = events.compactMap { event -> String? in
            if case let .textDelta(accumulated) = event { return accumulated }
            return nil
        }
        // Only one text delta — the empty-string chunk at the start is ignored.
        #expect(textEvents == ["Ok"])
    }
}
