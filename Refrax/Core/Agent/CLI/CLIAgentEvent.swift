import Foundation

/// One step of a CLI agent turn, decoded from a JSONL output line.
nonisolated enum CLIAgentEvent: Equatable, Sendable {
    /// The CLI assigned the conversation an id; pass it back to resume.
    case sessionStarted(id: String)

    /// A new assistant message begins; its text starts a new paragraph.
    case messageStarted

    /// A streamed chunk of assistant text.
    case textDelta(String)

    /// A complete assistant message delivered in one piece.
    case messageText(String)

    /// The agent called a tool. `detail` is a one-line summary of the input.
    case toolStarted(id: String, name: String, detail: String?)

    /// A tool call returned.
    case toolFinished(id: String, output: String, isError: Bool)

    /// The turn ended successfully.
    case finished(usage: CLIAgentUsage?)

    /// The turn ended with an error.
    case failed(String)

    /// A non-fatal error report; surfaced only if the process exits without finishing.
    case errorNotice(String)
}

/// Token counts reported at the end of a turn.
nonisolated struct CLIAgentUsage: Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - Shared Helpers

nonisolated enum CLIAgentEventDecoding {
    /// Longest tool output kept for display.
    static let maxToolOutputLength = 2_000

    /// Longest tool detail kept for display.
    static let maxDetailLength = 200

    static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// First line of `text`, trimmed and capped at ``maxDetailLength``.
    static func oneLine(_ text: String) -> String {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > maxDetailLength ? String(trimmed.prefix(maxDetailLength)) + "…" : trimmed
    }

    static func capped(_ text: String) -> String {
        text.count > maxToolOutputLength ? String(text.prefix(maxToolOutputLength)) + "…" : text
    }
}

// MARK: - Claude Code

/// Decodes `claude -p --output-format stream-json --verbose --include-partial-messages`.
///
/// Text streams through `stream_event` deltas; tool calls come from the
/// complete `assistant` messages and their results from `user` messages.
/// Events from subagents (non-null `parent_tool_use_id`) are skipped.
nonisolated enum ClaudeCodeStreamParser {
    /// Input keys that summarize a tool call, in order of preference.
    private static let detailKeys = ["command", "url", "file_path", "query", "pattern", "skill", "prompt"]

    static func events(fromLine line: String) -> [CLIAgentEvent] {
        guard let json = CLIAgentEventDecoding.jsonObject(line),
              let type = json["type"] as? String else { return [] }
        if json["parent_tool_use_id"] is String { return [] }

        switch type {
        case "system":
            guard json["subtype"] as? String == "init",
                  let sessionID = json["session_id"] as? String else { return [] }
            return [.sessionStarted(id: sessionID)]

        case "stream_event":
            return streamEvents(json["event"] as? [String: Any])

        case "assistant":
            let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap(toolStarted)

        case "user":
            let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap(toolFinished)

        case "result":
            return [result(json)]

        default:
            return []
        }
    }

    private static func streamEvents(_ event: [String: Any]?) -> [CLIAgentEvent] {
        switch event?["type"] as? String {
        case "message_start":
            return [.messageStarted]
        case "content_block_delta":
            guard let delta = event?["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String,
                  !text.isEmpty else { return [] }
            return [.textDelta(text)]
        default:
            return []
        }
    }

    private static func toolStarted(_ block: [String: Any]) -> CLIAgentEvent? {
        guard block["type"] as? String == "tool_use",
              let id = block["id"] as? String,
              let name = block["name"] as? String else { return nil }
        let input = block["input"] as? [String: Any] ?? [:]
        let detail = detailKeys.lazy
            .compactMap { input[$0] as? String }
            .first
            .map(CLIAgentEventDecoding.oneLine)
        return .toolStarted(id: id, name: name, detail: detail)
    }

    private static func toolFinished(_ block: [String: Any]) -> CLIAgentEvent? {
        guard block["type"] as? String == "tool_result",
              let id = block["tool_use_id"] as? String else { return nil }
        let output: String = if let text = block["content"] as? String {
            text
        } else if let parts = block["content"] as? [[String: Any]] {
            parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            ""
        }
        return .toolFinished(
            id: id,
            output: CLIAgentEventDecoding.capped(output),
            isError: block["is_error"] as? Bool ?? false,
        )
    }

    private static func result(_ json: [String: Any]) -> CLIAgentEvent {
        let isError = json["is_error"] as? Bool ?? false
        guard !isError, json["subtype"] as? String == "success" else {
            let message = (json["result"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (json["errors"] as? [String])?.joined(separator: "\n")
                ?? "Claude Code stopped: \(json["subtype"] as? String ?? "unknown error")"
            return .failed(message)
        }
        let usage = (json["usage"] as? [String: Any]).map { usage in
            let input = (usage["input_tokens"] as? Int ?? 0)
                + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                + (usage["cache_read_input_tokens"] as? Int ?? 0)
            return CLIAgentUsage(inputTokens: input, outputTokens: usage["output_tokens"] as? Int ?? 0)
        }
        return .finished(usage: usage)
    }
}

// MARK: - Codex

/// Decodes `codex exec --json`.
///
/// Codex reports whole items: an `agent_message` arrives complete in
/// `item.completed`, and tool items (`command_execution`, `mcp_tool_call`,
/// `web_search`, `file_change`) arrive as `item.started` / `item.completed`
/// pairs keyed by item id.
nonisolated enum CodexExecStreamParser {
    static func events(fromLine line: String) -> [CLIAgentEvent] {
        guard let json = CLIAgentEventDecoding.jsonObject(line),
              let type = json["type"] as? String else { return [] }

        switch type {
        case "thread.started":
            guard let threadID = json["thread_id"] as? String else { return [] }
            return [.sessionStarted(id: threadID)]

        case "item.started":
            guard let item = json["item"] as? [String: Any] else { return [] }
            return toolStarted(item).map { [$0] } ?? []

        case "item.completed":
            guard let item = json["item"] as? [String: Any] else { return [] }
            return completed(item)

        case "turn.completed":
            let usage = (json["usage"] as? [String: Any]).map { usage in
                CLIAgentUsage(
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                )
            }
            return [.finished(usage: usage)]

        case "turn.failed":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Codex turn failed"
            return [.failed(message)]

        case "error":
            guard let message = json["message"] as? String else { return [] }
            return [.errorNotice(message)]

        default:
            return []
        }
    }

    private static func completed(_ item: [String: Any]) -> [CLIAgentEvent] {
        switch item["type"] as? String {
        case "agent_message":
            guard let text = item["text"] as? String, !text.isEmpty else { return [] }
            return [.messageText(text)]
        case "error":
            guard let message = item["message"] as? String else { return [] }
            return [.errorNotice(message)]
        default:
            // Items can complete without a matching `item.started`, so the
            // start is repeated; consumers deduplicate by id.
            guard let started = toolStarted(item), let id = item["id"] as? String else { return [] }
            return [started, .toolFinished(id: id, output: output(of: item), isError: isError(item))]
        }
    }

    private static func toolStarted(_ item: [String: Any]) -> CLIAgentEvent? {
        guard let id = item["id"] as? String else { return nil }
        switch item["type"] as? String {
        case "command_execution":
            let command = (item["command"] as? String).map(CLIAgentEventDecoding.oneLine)
            return .toolStarted(id: id, name: "shell", detail: command)
        case "mcp_tool_call":
            let server = item["server"] as? String ?? "mcp"
            let tool = item["tool"] as? String ?? "tool"
            return .toolStarted(id: id, name: "\(server).\(tool)", detail: nil)
        case "web_search":
            let query = (item["query"] as? String).map(CLIAgentEventDecoding.oneLine)
            return .toolStarted(id: id, name: "web_search", detail: query)
        case "file_change":
            return .toolStarted(id: id, name: "file_change", detail: nil)
        default:
            return nil
        }
    }

    private static func output(of item: [String: Any]) -> String {
        if let output = item["aggregated_output"] as? String {
            return CLIAgentEventDecoding.capped(output)
        }
        if let error = item["error"] as? [String: Any], let message = error["message"] as? String {
            return CLIAgentEventDecoding.capped(message)
        }
        return ""
    }

    private static func isError(_ item: [String: Any]) -> Bool {
        if item["status"] as? String == "failed" { return true }
        if let exitCode = item["exit_code"] as? Int { return exitCode != 0 }
        return false
    }
}

// MARK: - Line Buffer

/// Splits a byte stream into newline-terminated lines.
nonisolated struct JSONLineBuffer: Sendable {
    private var pending = Data()

    /// Appends a chunk and returns every line it completed.
    mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pending[pending.startIndex ..< newline]
            pending.removeSubrange(pending.startIndex ... newline)
            let line = String(decoding: lineData, as: UTF8.self)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    /// Returns the unterminated remainder, if any, and empties the buffer.
    mutating func flush() -> String? {
        defer { pending.removeAll() }
        let line = String(decoding: pending, as: UTF8.self)
        return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : line
    }
}

// MARK: - Transcript

/// Accumulates one turn's text and tool blocks in the shape ``ChatEventPayload`` carries.
nonisolated struct CLIRunTranscript: Sendable {
    typealias Block = ChatEventPayload.ChatMessage.ContentBlock

    /// All assistant text so far, paragraphs separated by blank lines.
    private(set) var text = ""

    /// Tool use and tool result blocks in arrival order, one of each per id.
    private(set) var toolBlocks: [Block] = []

    private var startsNewParagraph = false
    private var startedToolIDs: Set<String> = []
    private var finishedToolIDs: Set<String> = []

    /// What changed after applying an event.
    nonisolated enum Change {
        case none
        case text
        case tool(Block)
    }

    mutating func apply(_ event: CLIAgentEvent) -> Change {
        switch event {
        case .messageStarted:
            startsNewParagraph = !text.isEmpty
            return .none

        case let .textDelta(chunk):
            appendText(chunk)
            return .text

        case let .messageText(message):
            startsNewParagraph = !text.isEmpty
            appendText(message)
            return .text

        case let .toolStarted(id, name, detail):
            guard startedToolIDs.insert(id).inserted else { return .none }
            let block = Block(type: "tool_use", text: detail, id: id, name: name)
            toolBlocks.append(block)
            startsNewParagraph = !text.isEmpty
            return .tool(block)

        case let .toolFinished(id, output, isError):
            guard finishedToolIDs.insert(id).inserted else { return .none }
            let block = Block(type: "tool_result", text: output, toolUseId: id, isError: isError)
            toolBlocks.append(block)
            return .tool(block)

        case .sessionStarted, .finished, .failed, .errorNotice:
            return .none
        }
    }

    private mutating func appendText(_ chunk: String) {
        if startsNewParagraph {
            text += "\n\n"
            startsNewParagraph = false
        }
        text += chunk
    }
}
