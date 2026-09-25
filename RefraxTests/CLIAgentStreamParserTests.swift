import Foundation
import Testing

@testable import Refrax

// MARK: - Claude Code

/// Lines follow `claude -p --output-format stream-json --verbose
/// --include-partial-messages` output captured from Claude Code 2.1.282,
/// trimmed to the fields the parser reads.
@Suite("ClaudeCodeStreamParser — stream-json events", .tags(.agentMultiProvider))
struct ClaudeCodeStreamParserTests {
    @Test("system/init reports the session id")
    func initEvent() {
        let events = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"system","subtype":"init","cwd":"/tmp/s","session_id":"7a79d8b9-ea7c-4b80-b3c6-0fcc39bff405","tools":["Bash"],"model":"claude-haiku-4-5-20251001"}
        """)
        #expect(events == [.sessionStarted(id: "7a79d8b9-ea7c-4b80-b3c6-0fcc39bff405")])
    }

    @Test("Hook and status system events are ignored")
    func otherSystemEvents() {
        let lines = [
            #"{"type":"system","subtype":"hook_started","hook_id":"h","session_id":"s"}"#,
            #"{"type":"system","subtype":"status","status":"requesting","session_id":"s"}"#,
            #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"},"session_id":"s"}"#,
        ]
        #expect(lines.flatMap(ClaudeCodeStreamParser.events(fromLine:)).isEmpty)
    }

    @Test("Text deltas stream; thinking deltas are dropped")
    func textDeltas() {
        let lines = [
            #"{"type":"stream_event","event":{"type":"message_start","message":{"role":"assistant","content":[]}},"session_id":"s","parent_tool_use_id":null}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}},"session_id":"s","parent_tool_use_id":null}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"ok"}},"session_id":"s","parent_tool_use_id":null}"#,
        ]
        #expect(lines.flatMap(ClaudeCodeStreamParser.events(fromLine:)) == [.messageStarted, .textDelta("ok")])
    }

    @Test("Assistant text blocks are ignored because deltas already carried them")
    func assistantTextIgnored() {
        let events = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"parent_tool_use_id":null,"session_id":"s"}
        """)
        #expect(events.isEmpty)
    }

    @Test("Tool use and tool result map to tool events with a one-line detail")
    func toolRoundTrip() {
        let use = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"refrax-ctl read --scope text\\necho done","description":"Read page"}}]},"parent_tool_use_id":null,"session_id":"s"}
        """)
        #expect(use == [.toolStarted(id: "toolu_1", name: "Bash", detail: "refrax-ctl read --scope text")])

        let result = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":[{"type":"text","text":"Example Domain"}],"is_error":false}]},"parent_tool_use_id":null,"session_id":"s"}
        """)
        #expect(result == [.toolFinished(id: "toolu_1", output: "Example Domain", isError: false)])
    }

    @Test("String tool results and error flags are read")
    func toolErrorResult() {
        let events = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_2","content":"Permission denied","is_error":true}]},"parent_tool_use_id":null,"session_id":"s"}
        """)
        #expect(events == [.toolFinished(id: "toolu_2", output: "Permission denied", isError: true)])
    }

    @Test("Subagent events are skipped")
    func subagentSkipped() {
        let events = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_9","name":"Read","input":{"file_path":"/x"}}]},"parent_tool_use_id":"toolu_parent","session_id":"s"}
        """)
        #expect(events.isEmpty)
    }

    @Test("Successful result finishes with summed input usage")
    func successResult() {
        let events = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":5,"output_tokens":7}}
        """)
        #expect(events == [.finished(usage: CLIAgentUsage(inputTokens: 115, outputTokens: 7))])
    }

    @Test("Error result fails with its message")
    func errorResult() {
        let events = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login","session_id":"s"}
        """)
        #expect(events == [.failed("Not logged in · Please run /login")])

        let maxTurns = ClaudeCodeStreamParser.events(fromLine: """
        {"type":"result","subtype":"error_max_turns","is_error":true,"session_id":"s"}
        """)
        #expect(maxTurns == [.failed("Claude Code stopped: error_max_turns")])
    }

    @Test("Malformed lines produce no events")
    func malformed() {
        #expect(ClaudeCodeStreamParser.events(fromLine: "not json").isEmpty)
        #expect(ClaudeCodeStreamParser.events(fromLine: "{\"no_type\":1}").isEmpty)
    }
}

// MARK: - Codex

/// Lines follow the `codex exec --json` event schema (thread/turn/item events).
@Suite("CodexExecStreamParser — exec JSONL events", .tags(.agentMultiProvider))
struct CodexExecStreamParserTests {
    @Test("thread.started reports the thread id")
    func threadStarted() {
        let events = CodexExecStreamParser.events(fromLine: #"{"type":"thread.started","thread_id":"0199a213-81c0-7800-8aa1-bbab2a035a53"}"#)
        #expect(events == [.sessionStarted(id: "0199a213-81c0-7800-8aa1-bbab2a035a53")])
    }

    @Test("Command execution maps to shell tool events")
    func commandExecution() {
        let started = CodexExecStreamParser.events(fromLine: """
        {"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"bash -lc 'refrax-ctl read'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
        """)
        #expect(started == [.toolStarted(id: "item_1", name: "shell", detail: "bash -lc 'refrax-ctl read'")])

        let completed = CodexExecStreamParser.events(fromLine: """
        {"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"bash -lc 'refrax-ctl read'","aggregated_output":"Example Domain\\n","exit_code":0,"status":"completed"}}
        """)
        #expect(completed == [
            .toolStarted(id: "item_1", name: "shell", detail: "bash -lc 'refrax-ctl read'"),
            .toolFinished(id: "item_1", output: "Example Domain\n", isError: false),
        ])
    }

    @Test("A nonzero exit code marks the command as failed")
    func failedCommand() {
        let events = CodexExecStreamParser.events(fromLine: """
        {"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"false","aggregated_output":"","exit_code":1,"status":"failed"}}
        """)
        #expect(events.last == .toolFinished(id: "item_2", output: "", isError: true))
    }

    @Test("Agent messages arrive whole")
    func agentMessage() {
        let events = CodexExecStreamParser.events(fromLine: #"{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"The page is about examples."}}"#)
        #expect(events == [.messageText("The page is about examples.")])
    }

    @Test("Reasoning items are ignored")
    func reasoningIgnored() {
        let events = CodexExecStreamParser.events(fromLine: #"{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"thinking"}}"#)
        #expect(events.isEmpty)
    }

    @Test("turn.completed finishes with usage; turn.failed fails")
    func turnEnd() {
        let completed = CodexExecStreamParser.events(fromLine: #"{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"output_tokens":122}}"#)
        #expect(completed == [.finished(usage: CLIAgentUsage(inputTokens: 24_763, outputTokens: 122))])

        let failed = CodexExecStreamParser.events(fromLine: #"{"type":"turn.failed","error":{"message":"stream disconnected"}}"#)
        #expect(failed == [.failed("stream disconnected")])
    }

    @Test("Top-level errors are notices")
    func errorNotice() {
        let events = CodexExecStreamParser.events(fromLine: #"{"type":"error","message":"Reconnecting... 1/5"}"#)
        #expect(events == [.errorNotice("Reconnecting... 1/5")])
    }
}

// MARK: - Line Buffer and Transcript

@Suite("CLI agent line buffer and transcript", .tags(.agentMultiProvider))
struct CLIRunTranscriptTests {
    @Test("Lines split across chunks are reassembled")
    func lineBuffer() {
        var buffer = JSONLineBuffer()
        let first = buffer.append(Data("{\"a\":1}\n{\"b\"".utf8))
        let second = buffer.append(Data(":2}\n\n".utf8))
        let third = buffer.append(Data("{\"c\":3}".utf8))
        let remainder = buffer.flush()
        let empty = buffer.flush()

        #expect(first == ["{\"a\":1}"])
        #expect(second == ["{\"b\":2}"])
        #expect(third.isEmpty)
        #expect(remainder == "{\"c\":3}")
        #expect(empty == nil)
    }

    @Test("Text after a tool call starts a new paragraph")
    func paragraphs() {
        var transcript = CLIRunTranscript()
        _ = transcript.apply(.messageStarted)
        _ = transcript.apply(.textDelta("Let me read "))
        _ = transcript.apply(.textDelta("the page."))
        _ = transcript.apply(.toolStarted(id: "t1", name: "Bash", detail: "refrax-ctl read"))
        _ = transcript.apply(.toolFinished(id: "t1", output: "…", isError: false))
        _ = transcript.apply(.messageStarted)
        _ = transcript.apply(.textDelta("It is about examples."))

        #expect(transcript.text == "Let me read the page.\n\nIt is about examples.")
        #expect(transcript.toolBlocks.map(\.type) == ["tool_use", "tool_result"])
        #expect(transcript.toolBlocks.first?.text == "refrax-ctl read")
    }

    @Test("Repeated tool events for one id are deduplicated")
    func deduplicatesTools() {
        var transcript = CLIRunTranscript()
        _ = transcript.apply(.toolStarted(id: "item_1", name: "shell", detail: nil))
        _ = transcript.apply(.toolStarted(id: "item_1", name: "shell", detail: nil))
        _ = transcript.apply(.toolFinished(id: "item_1", output: "", isError: false))
        _ = transcript.apply(.toolFinished(id: "item_1", output: "", isError: false))
        #expect(transcript.toolBlocks.count == 2)
    }

    @Test("Whole Codex messages are separated by blank lines")
    func wholeMessages() {
        var transcript = CLIRunTranscript()
        _ = transcript.apply(.messageText("First."))
        _ = transcript.apply(.messageText("Second."))
        #expect(transcript.text == "First.\n\nSecond.")
    }
}

// MARK: - Arguments

@Suite("CLIAgentRuntime — argument lists", .tags(.agentMultiProvider))
struct CLIAgentRuntimeArgumentTests {
    @Test("Claude Code resumes the session and allows only refrax-ctl in Bash")
    func claudeCodeArguments() {
        let arguments = CLIAgentRuntime.claudeCode.arguments(
            sessionID: "abc",
            model: "sonnet",
            systemPrompt: "Be brief.",
            refraxCtlPath: "/usr/local/bin/refrax-ctl",
            imagePaths: [],
        )
        #expect(arguments.first == "-p")
        #expect(arguments.contains("--include-partial-messages"))
        #expect(pair("--resume", in: arguments) == "abc")
        #expect(pair("--model", in: arguments) == "sonnet")
        #expect(pair("--permission-mode", in: arguments) == "dontAsk")
        #expect(pair("--append-system-prompt", in: arguments) == "Be brief.")
        #expect(arguments.contains("Bash(/usr/local/bin/refrax-ctl:*)"))
        #expect(!arguments.contains("Bash"))
        #expect(!arguments.contains("--dangerously-skip-permissions"))
    }

    @Test("Claude Code omits --resume and --model on a fresh default session")
    func claudeCodeFreshArguments() {
        let arguments = CLIAgentRuntime.claudeCode.arguments(
            sessionID: nil, model: "", systemPrompt: "x", refraxCtlPath: nil, imagePaths: [],
        )
        #expect(!arguments.contains("--resume"))
        #expect(!arguments.contains("--model"))
    }

    @Test("Codex resume puts the thread id before the stdin marker")
    func codexResumeArguments() {
        let arguments = CLIAgentRuntime.codex.arguments(
            sessionID: "thread-1",
            model: "",
            systemPrompt: "Say \"hi\"\nthen stop",
            refraxCtlPath: nil,
            imagePaths: ["./attachments/a.png"],
        )
        #expect(Array(arguments.prefix(4)) == ["exec", "resume", "-i", "./attachments/a.png"])
        #expect(Array(arguments.suffix(2)) == ["thread-1", "-"])
        #expect(arguments.contains("--json"))
        #expect(arguments.contains(#"developer_instructions="Say \"hi\"\nthen stop""#))
    }

    private func pair(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
