import Foundation
import OSLog

/// Agent chat client that runs a local coding-agent CLI (Claude Code or Codex)
/// as the reasoning runtime.
///
/// Each user message spawns one CLI process that resumes the conversation's
/// CLI session, reads the prompt from standard input, and streams JSONL on
/// standard output. The agent acts on the browser by running `refrax-ctl`, so
/// this client advertises no in-app tools; the CLI's own tool calls are
/// forwarded as `tool_use` / `tool_result` blocks for display.
///
/// Each conversation gets a working directory under
/// `Application Support/<bundle id>/Agent/Sessions/<id>`, which keeps project
/// `CLAUDE.md` / `AGENTS.md` files from the user's folders out of the context
/// and gives the agent a scratch space for screenshots and attachments.
actor LocalCLIAgentClient: AgentChatClientProtocol {
    // MARK: - Types

    nonisolated enum ClientError: Error, LocalizedError {
        case notInstalled(CLIAgentRuntime)
        case notConnected
        case busy
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case let .notInstalled(runtime):
                "\(runtime.displayName) was not found. \(runtime.installHint)"
            case .notConnected:
                "The agent is not connected"
            case .busy:
                "The agent is still answering the previous message"
            case let .launchFailed(reason):
                "Could not start the agent: \(reason)"
            }
        }
    }

    /// Conversation state kept on disk so a relaunch resumes the same CLI session.
    private nonisolated struct PersistedState: Codable, Sendable {
        var conversationID: String
        var sessionID: String?
        var messages: [PersistedMessage]

        static func fresh() -> PersistedState {
            PersistedState(conversationID: UUID().uuidString, sessionID: nil, messages: [])
        }
    }

    private nonisolated struct PersistedMessage: Codable, Sendable {
        let role: String
        let text: String
        let timestamp: Date
    }

    /// Progress of the turn being streamed.
    private nonisolated struct RunProgress {
        let runId: String
        var transcript = CLIRunTranscript()
        var seq = 0
        var isTerminal = false
        var errorNotice: String?
    }

    private nonisolated enum Constants {
        /// Grace period for output to close after the process exits; a
        /// grandchild holding the pipe open would otherwise stall the turn.
        static let outputGracePeriod: Duration = .seconds(2)
        /// Time between SIGINT and SIGTERM when aborting.
        static let terminationGracePeriod: Duration = .seconds(3)
        /// Bytes of standard error kept for error messages.
        static let stderrTailBytes = 4_096
        static let messageHistoryLimit = 200
    }

    // MARK: - State

    private let runtime: CLIAgentRuntime
    private let model: String
    private let stateURL: URL

    private(set) var connectionState: AgentConnectionState = .disconnected
    private var chatEventHandler: (@Sendable (ChatEventPayload) -> Void)?
    private var connectionStateHandler: (@Sendable (AgentConnectionState) -> Void)?

    private var executableURL: URL?
    private var state: PersistedState

    /// The run whose output is still being forwarded, and its process id.
    private var activeRun: (runId: String, pid: pid_t)?
    private var abortedRunIDs: Set<String> = []

    // MARK: - Initialization

    /// - Parameters:
    ///   - runtime: The CLI to drive.
    ///   - model: Model slug for the CLI, or empty for its default.
    init(runtime: CLIAgentRuntime, model: String) {
        self.runtime = runtime
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let stateURL = Self.agentDirectory.appending(path: "\(runtime.rawValue).json")
        self.stateURL = stateURL
        self.state = Self.loadState(from: stateURL) ?? .fresh()
    }

    deinit {
        if let activeRun {
            Self.terminate(pid: activeRun.pid)
        }
    }

    // MARK: - Connection

    func connect() async throws {
        updateConnectionState(.connecting)
        guard let url = await CLIAgentLocator.locate(runtime) else {
            updateConnectionState(.disconnected)
            throw ClientError.notInstalled(runtime)
        }
        executableURL = url
        updateConnectionState(.connected)
        Logger.info("[CLIAgent] \(runtime.displayName) at \(url.path)", category: Logger.agent)
    }

    func disconnect() {
        if let activeRun {
            abortedRunIDs.insert(activeRun.runId)
            Self.terminate(pid: activeRun.pid)
            self.activeRun = nil
        }
        updateConnectionState(.disconnected)
    }

    // MARK: - Chat Operations

    func sendChatMessage(
        sessionKey _: String,
        message: String,
        attachments: [ChatSendParams.ChatAttachment]?,
    ) async throws -> String {
        guard connectionState.isConnected, let executableURL else {
            throw ClientError.notConnected
        }
        guard activeRun == nil else {
            throw ClientError.busy
        }

        let runId = UUID().uuidString
        let directory = try sessionDirectory()
        let imagePaths = writeAttachments(attachments ?? [], into: directory)
        let refraxCtlPath = CLIAgentLocator.refraxCtlPath

        var prompt = message
        if runtime == .claudeCode, !imagePaths.isEmpty {
            prompt += "\n\n[Attached images: view them with Read]\n" + imagePaths.joined(separator: "\n")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = runtime.arguments(
            sessionID: state.sessionID,
            model: model,
            systemPrompt: ClaudeSystemPrompt.cliInstructions(refraxCtlPath: refraxCtlPath),
            refraxCtlPath: refraxCtlPath,
            imagePaths: imagePaths,
        )
        process.currentDirectoryURL = directory
        process.environment = CLIAgentLocator.environment(binary: executableURL, refraxCtlPath: refraxCtlPath)

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let (outputChunks, outputContinuation) = AsyncStream.makeStream(of: Data.self)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                outputContinuation.finish()
            } else {
                outputContinuation.yield(data)
            }
        }
        let (errorChunks, errorContinuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingNewest(64),
        )
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                errorContinuation.finish()
            } else {
                errorContinuation.yield(data)
            }
        }
        let (exitCodes, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            outputContinuation.finish()
            errorContinuation.finish()
            throw ClientError.launchFailed(error.localizedDescription)
        }

        let pid = process.processIdentifier
        CLIProcessRegistry.register(pid)
        activeRun = (runId, pid)

        // The child may exit before reading its input; EPIPE beats a SIGPIPE that kills Refrax.
        let writer = input.fileHandleForWriting
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? writer.write(contentsOf: Data(prompt.utf8))
        try? writer.close()

        state.messages.append(PersistedMessage(role: "user", text: message, timestamp: Date()))
        persistState()

        Task(name: "\(runtime.displayName) turn") {
            await self.stream(
                runId: runId,
                process: process,
                output: outputChunks,
                outputContinuation: outputContinuation,
                errors: errorChunks,
                errorContinuation: errorContinuation,
                exitCodes: exitCodes,
            )
        }

        return runId
    }

    func fetchChatHistory(sessionKey _: String, limit: Int) async throws -> ChatHistoryResponse {
        let messages = state.messages.suffix(limit).map { message in
            ChatHistoryResponse.HistoryMessage(
                role: message.role,
                content: [.init(type: "text", text: message.text, source: nil)],
                timestamp: Int(message.timestamp.timeIntervalSince1970 * 1_000),
            )
        }
        return ChatHistoryResponse(messages: messages, thinkingLevel: nil)
    }

    func abortChat(sessionKey _: String, runId: String) async throws {
        abortedRunIDs.insert(runId)
        if let activeRun, activeRun.runId == runId {
            Self.interrupt(pid: activeRun.pid)
            self.activeRun = nil
        }
        emit(ChatEventPayload(
            runId: runId,
            sessionKey: runtime.rawValue,
            seq: 0,
            state: .aborted,
            message: nil,
            errorMessage: nil,
            usage: nil,
            stopReason: "aborted",
        ))
    }

    func clearConversation() async {
        if let activeRun {
            abortedRunIDs.insert(activeRun.runId)
            Self.terminate(pid: activeRun.pid)
            self.activeRun = nil
        }
        let previousDirectory = Self.sessionsDirectory.appending(path: state.conversationID)
        try? FileManager.default.removeItem(at: previousDirectory)
        state = .fresh()
        persistState()
    }

    func setChatEventHandler(_ handler: @escaping @Sendable (ChatEventPayload) -> Void) {
        chatEventHandler = handler
    }

    func setConnectionStateHandler(_ handler: @escaping @Sendable (AgentConnectionState) -> Void) {
        connectionStateHandler = handler
    }

    // MARK: - Streaming

    private func stream(
        runId: String,
        process: Process,
        output: AsyncStream<Data>,
        outputContinuation: AsyncStream<Data>.Continuation,
        errors: AsyncStream<Data>,
        errorContinuation: AsyncStream<Data>.Continuation,
        exitCodes: AsyncStream<Int32>,
    ) async {
        let stderrTail = Task(name: "\(runtime.displayName) stderr") { () -> String in
            var tail = Data()
            for await chunk in errors {
                tail.append(chunk)
                if tail.count > Constants.stderrTailBytes * 2 {
                    tail = tail.suffix(Constants.stderrTailBytes)
                }
            }
            return String(decoding: tail.suffix(Constants.stderrTailBytes), as: UTF8.self)
        }
        let exitStatus = Task(name: "\(runtime.displayName) exit") { () -> Int32 in
            var status: Int32 = -1
            for await code in exitCodes {
                status = code
            }
            return status
        }
        let outputDeadline = Task(name: "\(runtime.displayName) output deadline") {
            _ = await exitStatus.value
            try? await Task.sleep(for: Constants.outputGracePeriod)
            guard !Task.isCancelled else { return }
            outputContinuation.finish()
            errorContinuation.finish()
        }

        var progress = RunProgress(runId: runId)
        var lines = JSONLineBuffer()
        for await chunk in output {
            for line in lines.append(chunk) {
                handle(line: line, progress: &progress)
            }
        }
        if let line = lines.flush() {
            handle(line: line, progress: &progress)
        }

        let status = await exitStatus.value
        let stderr = await stderrTail.value
        outputDeadline.cancel()
        CLIProcessRegistry.unregister(process.processIdentifier)

        if !progress.isTerminal {
            let detail = progress.errorNotice
                ?? Self.lastLines(of: stderr)
                ?? "exited with status \(status)"
            finishWithError(runId: runId, message: "\(runtime.displayName): \(detail)", progress: &progress)
        }
        abortedRunIDs.remove(runId)
    }

    private func handle(line: String, progress: inout RunProgress) {
        let events = switch runtime {
        case .claudeCode: ClaudeCodeStreamParser.events(fromLine: line)
        case .codex: CodexExecStreamParser.events(fromLine: line)
        }
        for event in events {
            apply(event, progress: &progress)
        }
    }

    private func apply(_ event: CLIAgentEvent, progress: inout RunProgress) {
        switch event {
        case let .sessionStarted(id):
            if state.sessionID != id {
                state.sessionID = id
                persistState()
            }
            return
        case let .errorNotice(message):
            progress.errorNotice = message
            return
        case let .failed(message):
            finishWithError(runId: progress.runId, message: message, progress: &progress)
            return
        case let .finished(usage):
            finish(usage: usage, progress: &progress)
            return
        case .messageStarted, .textDelta, .messageText, .toolStarted, .toolFinished:
            break
        }

        guard !progress.isTerminal else { return }
        let blocks: [CLIRunTranscript.Block] = switch progress.transcript.apply(event) {
        case .none: []
        case .text: [.init(type: "text", text: progress.transcript.text)]
        case let .tool(block): [block]
        }
        guard !blocks.isEmpty else { return }
        progress.seq += 1
        emitIfLive(ChatEventPayload(
            runId: progress.runId,
            sessionKey: runtime.rawValue,
            seq: progress.seq,
            state: .delta,
            message: ChatEventPayload.ChatMessage(role: "assistant", content: blocks, timestamp: nil),
            errorMessage: nil,
            usage: nil,
            stopReason: nil,
        ))
    }

    private func finish(usage: CLIAgentUsage?, progress: inout RunProgress) {
        guard !progress.isTerminal else { return }
        progress.isTerminal = true
        releaseActiveRun(progress.runId)

        let text = progress.transcript.text
        var blocks = progress.transcript.toolBlocks
        if !text.isEmpty {
            blocks.append(.init(type: "text", text: text))
            state.messages.append(PersistedMessage(role: "assistant", text: text, timestamp: Date()))
            state.messages = Array(state.messages.suffix(Constants.messageHistoryLimit))
            persistState()
        }

        emitIfLive(ChatEventPayload(
            runId: progress.runId,
            sessionKey: runtime.rawValue,
            seq: progress.seq + 1,
            state: .final,
            message: ChatEventPayload.ChatMessage(
                role: "assistant",
                content: blocks,
                timestamp: Int(Date().timeIntervalSince1970 * 1_000),
            ),
            errorMessage: nil,
            usage: usage.map {
                ChatEventPayload.ChatUsage(input: $0.inputTokens, output: $0.outputTokens, totalTokens: $0.inputTokens + $0.outputTokens)
            },
            stopReason: "end_turn",
        ))
    }

    private func finishWithError(runId: String, message: String, progress: inout RunProgress) {
        guard !progress.isTerminal else { return }
        progress.isTerminal = true
        releaseActiveRun(runId)
        Logger.error("[CLIAgent] \(message)", category: Logger.agent)
        emitIfLive(ChatEventPayload(
            runId: runId,
            sessionKey: runtime.rawValue,
            seq: 0,
            state: .error,
            message: nil,
            errorMessage: message,
            usage: nil,
            stopReason: nil,
        ))
    }

    /// Frees the client for the next message once the turn has an answer,
    /// even while the process is still shutting down.
    private func releaseActiveRun(_ runId: String) {
        if activeRun?.runId == runId {
            activeRun = nil
        }
    }

    private func emitIfLive(_ payload: ChatEventPayload) {
        guard !abortedRunIDs.contains(payload.runId) else { return }
        emit(payload)
    }

    private func emit(_ payload: ChatEventPayload) {
        chatEventHandler?(payload)
    }

    private func updateConnectionState(_ newState: AgentConnectionState) {
        connectionState = newState
        connectionStateHandler?(newState)
    }

    // MARK: - Files

    private nonisolated static var agentDirectory: URL {
        Directories.appStorage.appending(path: "Agent", directoryHint: .isDirectory)
    }

    private nonisolated static var sessionsDirectory: URL {
        agentDirectory.appending(path: "Sessions", directoryHint: .isDirectory)
    }

    private func sessionDirectory() throws -> URL {
        let directory = Self.sessionsDirectory.appending(path: state.conversationID, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ClientError.launchFailed(error.localizedDescription)
        }
        return directory
    }

    /// Writes image attachments under the session directory and returns
    /// their paths relative to it.
    private func writeAttachments(_ attachments: [ChatSendParams.ChatAttachment], into directory: URL) -> [String] {
        guard !attachments.isEmpty else { return [] }
        let folder = directory.appending(path: "attachments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return attachments.compactMap { attachment in
            guard let data = Data(base64Encoded: attachment.content) else { return nil }
            let fileExtension = attachment.mimeType.split(separator: "/").last.map(String.init) ?? "png"
            let name = "\(UUID().uuidString).\(fileExtension)"
            do {
                try data.write(to: folder.appending(path: name))
                return "./attachments/\(name)"
            } catch {
                Logger.warning("[CLIAgent] Could not write attachment: \(error.localizedDescription)", category: Logger.agent)
                return nil
            }
        }
    }

    private nonisolated static func loadState(from url: URL) -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func persistState() {
        do {
            try FileManager.default.createDirectory(at: Self.agentDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        } catch {
            Logger.warning("[CLIAgent] Could not save conversation state: \(error.localizedDescription)", category: Logger.agent)
        }
    }

    // MARK: - Process Control

    /// SIGINT first, so the CLI can save its session; SIGTERM if it lingers.
    private nonisolated static func interrupt(pid: pid_t) {
        kill(pid, SIGINT)
        Task(name: "CLI agent termination") {
            try? await Task.sleep(for: Constants.terminationGracePeriod)
            terminate(pid: pid)
        }
    }

    private nonisolated static func terminate(pid: pid_t) {
        guard CLIProcessRegistry.isRunning(pid) else { return }
        kill(pid, SIGTERM)
    }

    /// The last few non-empty lines of `text`, or `nil` when there are none.
    private nonisolated static func lastLines(of text: String, count: Int = 3) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.suffix(count).joined(separator: "\n")
    }
}
