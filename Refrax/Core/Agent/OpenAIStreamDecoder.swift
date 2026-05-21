import Foundation

/// Pure decoder for OpenAI Chat Completions SSE streams.
///
/// Accumulates `delta.content` and `delta.tool_calls` fragments across chunks,
/// indexed by `tool_calls[].index` as OpenAI specifies. The decoder is
/// deliberately stateful and standalone — the network loop in
/// ``OpenAICompatibleClient`` feeds it decoded JSON objects one chunk at a
/// time and calls ``finalize()`` when the stream ends.
nonisolated final class OpenAIStreamDecoder {
    // MARK: - Accumulated State

    /// Final result produced by ``finalize()``.
    struct Result: Sendable {
        var text: String
        var toolCalls: [DecodedToolCall]
        var stopReason: String?
        var usage: AgentMessage.TokenUsage?
    }

    /// A single tool call parsed from the stream.
    struct DecodedToolCall: Sendable, Equatable {
        var id: String
        var name: String
        var argumentsJSON: String
    }

    // MARK: - Events fed back to callers

    /// An event fired on each decoded chunk, surfaced so the client can
    /// stream text deltas to the UI without waiting for stream end.
    enum Event: Sendable, Equatable {
        /// Accumulated assistant text after processing the chunk.
        case textDelta(accumulated: String)
        /// Usage metadata (typically on the final chunk).
        case usage(AgentMessage.TokenUsage)
        /// The stream finished with this reason (e.g., `"tool_calls"`).
        case finish(reason: String)
    }

    // MARK: - Private State

    private var accumulatedText = ""
    private var toolCallsByIndex: [Int: PartialToolCall] = [:]
    private var toolCallOrder: [Int] = []
    private var stopReason: String?
    private var usage: AgentMessage.TokenUsage?

    private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments: String = ""
    }

    init() {}

    // MARK: - Feed

    /// Processes one decoded SSE chunk JSON.
    ///
    /// - Parameter json: The top-level JSON object (already decoded from
    ///   `data: {...}`). `[DONE]` lines should be handled by the caller
    ///   before calling this method.
    /// - Returns: Events triggered by this chunk (0+), in order.
    @discardableResult
    func consume(chunk json: [String: Any]) -> [Event] {
        var events: [Event] = []

        if let usageJSON = json["usage"] as? [String: Any] {
            let input = usageJSON["prompt_tokens"] as? Int ?? 0
            let output = usageJSON["completion_tokens"] as? Int ?? 0
            let tokens = AgentMessage.TokenUsage(inputTokens: input, outputTokens: output)
            usage = tokens
            events.append(.usage(tokens))
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first
        else {
            return events
        }

        if let finish = first["finish_reason"] as? String, !finish.isEmpty {
            stopReason = finish
            events.append(.finish(reason: finish))
        }

        guard let delta = first["delta"] as? [String: Any] else {
            return events
        }

        if let chunk = delta["content"] as? String, !chunk.isEmpty {
            accumulatedText += chunk
            events.append(.textDelta(accumulated: accumulatedText))
        }

        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                guard let index = call["index"] as? Int else { continue }
                var partial = toolCallsByIndex[index] ?? {
                    toolCallOrder.append(index)
                    return PartialToolCall()
                }()

                if let id = call["id"] as? String { partial.id = id }
                if let function = call["function"] as? [String: Any] {
                    if let name = function["name"] as? String { partial.name = name }
                    if let args = function["arguments"] as? String { partial.arguments += args }
                }
                toolCallsByIndex[index] = partial
            }
        }

        return events
    }

    // MARK: - Finalization

    /// Produces the final decoded result. `stopReason` is normalized so
    /// `"tool_calls"` becomes the Anthropic-canonical `"tool_use"` to
    /// match ``ClaudeDirectClient``.
    func finalize() -> Result {
        var decoded: [DecodedToolCall] = []
        for index in toolCallOrder {
            guard let partial = toolCallsByIndex[index],
                  let id = partial.id,
                  let name = partial.name
            else { continue }
            decoded.append(DecodedToolCall(id: id, name: name, argumentsJSON: partial.arguments))
        }

        let normalizedStop: String? = if stopReason == "tool_calls" {
            "tool_use"
        } else {
            stopReason
        }

        return Result(
            text: accumulatedText,
            toolCalls: decoded,
            stopReason: normalizedStop,
            usage: usage,
        )
    }
}
