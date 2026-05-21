import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

/// Constants for agent chat operations.
enum AgentChatConstants {
    /// Maximum total size for attachments (10MB - OpenResponses API limit).
    static let maxAttachmentBytes = 10_000_000

    /// Maximum size per image (5MB raw).
    /// The HTTP OpenResponses API supports up to 10MB per image, but we compress larger
    /// images to reduce bandwidth and improve upload speed. 5MB is a good balance.
    static let maxImageBytes = 5_000_000

    /// Minimum interval between streaming UI updates (100ms).
    static let streamingDebounceInterval: Duration = .milliseconds(100)
}

/// Observable manager for agent chat state.
///
/// Manages the chat session with an AI assistant via the agent chat client.
/// Provides reactive state for SwiftUI views and filters gateway artifacts
/// from the message stream.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │        AgentChatManager (@Observable)    │
/// │  • messages / displayMessages            │
/// │  • connectionState, isStreaming          │
/// │  • pendingAttachments                    │
/// └───────────────┬─────────────────────────┘
///                 │
///                 ▼
/// ┌─────────────────────────────────────────┐
/// │     AgentChatClientProtocol (actor)      │
/// │  • Connection lifecycle                  │
/// │  • Request/response correlation          │
/// │  • Event streaming                       │
/// └─────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// Inject via environment, then:
/// ```swift
/// @Environment(AgentChatManager.self) var chatManager
///
/// // Send message
/// await chatManager.sendMessage("Hello!")
///
/// // Access messages
/// ForEach(chatManager.messages) { message in
///     AgentMessageView(message: message)
/// }
/// ```
@Observable
@MainActor
final class AgentChatManager {
    // MARK: - Observable State

    /// Messages in the current conversation.
    private(set) var messages: [AgentMessage] = []

    /// Current connection state.
    private(set) var connectionState: AgentConnectionState = .disconnected

    /// Whether a response is currently streaming.
    private(set) var isStreaming: Bool = false

    /// Pending attachments to include with the next message.
    var pendingAttachments: [AgentMessage.ImageAttachment] = []

    /// Error to display to the user.
    private(set) var error: ChatError?

    /// Whether history is currently being loaded.
    private(set) var isLoadingHistory: Bool = false

    /// Whether the HTTP endpoint is available for large attachments.
    var isHTTPEndpointAvailable: Bool? {
        get async { await client.isHTTPEndpointAvailable }
    }

    /// Error message if HTTP endpoint is unavailable.
    var httpEndpointError: String? {
        get async { await client.httpEndpointError }
    }

    /// Whether pending attachments would require HTTP transport.
    var pendingAttachmentsRequireHTTP: Bool {
        let totalSize = pendingAttachments.reduce(0) { $0 + $1.sizeBytes }
        return totalSize > 300_000
    }

    // MARK: - Display Filtering

    /// Messages filtered for display, excluding gateway artifacts.
    ///
    /// Removes system messages, tool execution logs, raw JSON payloads,
    /// and other runtime artifacts that aren't part of the user-facing conversation.
    /// HEARTBEAT_OK messages are preserved (displayed as "Reply skipped" by the view).
    var displayMessages: [AgentMessage] {
        messages.filter { message in
            guard message.role != .system else { return false }
            if message.isEmpty { return false }

            let text = message.textContent
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Keep HEARTBEAT_OK (view renders as "Reply skipped")
            if trimmed == "HEARTBEAT_OK" { return true }

            // Exclude heartbeat prompt messages (system-initiated)
            if trimmed.contains("HEARTBEAT.md"), trimmed.contains("HEARTBEAT_OK") {
                return false
            }

            // Exclude tool execution logs and system notifications
            if text.hasPrefix("System: [") { return false }
            if text.hasPrefix("GatewayRestart:") { return false }
            if text.hasPrefix("ToolResult:") { return false }
            if text.hasPrefix("ToolCall:") { return false }
            if text.hasPrefix("Approval required") { return false }

            // Exclude raw JSON objects (likely system data)
            if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"), trimmed.contains("\"") {
                return false
            }

            // Exclude tool output (file content dumps, shell output)
            if Self.isLikelyToolOutput(trimmed) { return false }

            return true
        }
    }

    /// Detects messages that are clearly tool output (not legitimate agent responses).
    ///
    /// Conservative filtering — only matches patterns that couldn't be agent conversation.
    private static func isLikelyToolOutput(_ text: String) -> Bool {
        // Raw HTML dumps (not markdown, actual HTML tags at start)
        if text.hasPrefix("<p ") || text.hasPrefix("<picture") || text.hasPrefix("<!DOCTYPE") {
            return true
        }

        // Shell "(no output)" marker
        if text == "(no output)" { return true }

        // Directory listing output (ls -la)
        if text.hasPrefix("total "), text.contains("drwx") || text.contains("-rw-") {
            return true
        }

        // Git commit output
        if text.hasPrefix("[main ") || text.hasPrefix("[master "),
           text.contains(" files changed") || text.contains(" insertions(+)") || text.contains(" deletions(-)") {
            return true
        }

        // File content with line numbers (Claude Code read output format)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 10 {
            let lineNumberedCount = lines.prefix(5).count(where: { line in
                let str = String(line)
                return str.contains("→") && str.first?.isWhitespace == true
            })
            if lineNumberedCount >= 3 { return true }
        }

        // Very long raw HTML/code dump starting with markdown header
        if text.count > 2_000, text.hasPrefix("# "),
           text.contains("<p ") || text.contains("<img ") {
            return true
        }

        return false
    }

    // MARK: - Chat Error

    struct ChatError: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isRecoverable: Bool

        static func == (lhs: ChatError, rhs: ChatError) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Non-Observable State

    @ObservationIgnored
    private let client: any AgentChatClientProtocol

    @ObservationIgnored
    private let settings: BrowserSettings

    @ObservationIgnored
    private var streamingMessage: AgentMessage?

    @ObservationIgnored
    private var currentRunId: String?

    @ObservationIgnored
    private let sessionKey: String

    @ObservationIgnored
    private var hasLoadedHistory = false

    /// Pending streaming update (debounced).
    @ObservationIgnored
    private var pendingStreamingUpdate: AgentMessage?

    /// Task for debouncing streaming updates.
    @ObservationIgnored
    private var streamingDebounceTask: Task<Void, Never>?

    /// Tool bridge for Claude tool execution.
    @ObservationIgnored
    private var toolBridge: AgentToolBridge?

    /// Thought stream store for emitting agent activity thoughts.
    @ObservationIgnored
    var thoughtStreamStore: ThoughtStreamStore?

    // MARK: - Initialization

    /// Creates a chat manager with a custom client.
    init(settings: BrowserSettings, client: any AgentChatClientProtocol, sessionKey: String? = nil) {
        self.settings = settings
        self.sessionKey = sessionKey ?? settings.agentSessionKey
        self.client = client

        setupEventHandlers()
    }

    /// Configures tool definitions, system prompt, and executor for the active client.
    ///
    /// Must be called after the `RefraxControlServer` is created. Works for any
    /// client conforming to ``AgentChatClientProtocol`` — ``ClaudeDirectClient``
    /// stores the definitions natively, ``OpenAICompatibleClient`` translates
    /// them via ``OpenAIToolAdapter``, and ``MockAgentChatClient`` no-ops.
    func configureToolSystem(
        controlServer: RefraxControlServer,
        windowManager: WindowManager,
        userStyleManager: UserStyleManager,
        pagePool: WebPagePool,
        browserContext: @escaping @MainActor @Sendable () -> BrowserContext?,
    ) async {
        let bridge = AgentToolBridge(
            controlServer: controlServer,
            windowManager: windowManager,
            userStyleManager: userStyleManager,
            pagePool: pagePool,
        )
        bridge.thoughtStreamStore = thoughtStreamStore
        toolBridge = bridge

        await client.setToolDefinitions(AgentTools.definitions)

        await client.setSystemPromptBuilder { @MainActor in
            ClaudeSystemPrompt.build(context: browserContext())
        }

        await client.setToolExecutor { @MainActor name, input in
            await bridge.execute(toolName: name, input: input)
        }
    }

    private func setupEventHandlers() {
        Task {
            await client.setChatEventHandler { [weak self] payload in
                // Callback comes from actor (background), use DispatchQueue for MainActor hop
                DispatchQueue.main.async {
                    self?.handleChatEvent(payload)
                }
            }

            await client.setConnectionStateHandler { [weak self] state in
                DispatchQueue.main.async {
                    self?.handleConnectionStateChange(state)
                }
            }
        }
    }

    // MARK: - Connection Management

    /// Connects to the agent gateway.
    func connect() async {
        guard connectionState == .disconnected else { return }

        connectionState = .connecting

        do {
            try await client.connect()
            connectionState = .connected

            // Load history on first connect
            if !hasLoadedHistory {
                await loadHistory()
            }
        } catch {
            Logger.error("Connection failed: \(error.localizedDescription)", category: Logger.agent)
            connectionState = .disconnected
            self.error = ChatError(
                message: "Failed to connect: \(error.localizedDescription)",
                isRecoverable: true,
            )
        }
    }

    /// Disconnects from the gateway.
    func disconnect() {
        Task {
            await client.disconnect()
        }
        connectionState = .disconnected
    }

    // MARK: - Chat Operations

    /// Sends a message to the agent.
    ///
    /// - Parameters:
    ///   - text: The message text.
    ///   - context: Optional browser context to include.
    func sendMessage(_ text: String, context: BrowserContext? = nil) async {
        // Clear stale errors from previous interactions
        error = nil

        guard connectionState.isConnected else {
            error = ChatError(message: "Not connected to gateway", isRecoverable: true)
            return
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let userMessage = AgentMessage.user(text: text, attachments: pendingAttachments)
        messages.append(userMessage)
        pendingAttachments.removeAll()

        let finalText = buildMessage(text, includingContext: context)
        await performSend(userMessage: userMessage, messageText: finalText)
    }

    /// Aborts the current streaming response.
    func abortResponse() async {
        guard isStreaming, let runId = currentRunId else { return }

        do {
            try await client.abortChat(sessionKey: sessionKey, runId: runId)
        } catch {
            Logger.error("Failed to abort: \(error.localizedDescription)", category: Logger.agent)
        }

        // State will be updated by the aborted event
    }

    // MARK: - Debug: Page Extraction

    /// Runs page structure extraction on the active page and sends the result
    /// (with a screenshot) to the agent for evaluation.
    func debugExtractPage(page: WebPage) async {
        guard connectionState.isConnected else {
            error = ChatError(message: "Not connected to gateway", isRecoverable: true)
            return
        }

        // Take screenshot of visible area and compress to JPEG to stay under
        // the WebSocket attachment size limit (~5MB per image).
        var screenshotAttachment: AgentMessage.ImageAttachment?
        do {
            let pngData = try await ScreenshotService.takeScreenshot(of: page, mode: .visibleArea)
            if let bitmap = NSBitmapImageRep(data: pngData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                screenshotAttachment = AgentMessage.ImageAttachment(
                    data: jpegData,
                    mimeType: "image/jpeg",
                    fileName: "page-screenshot.jpg",
                )
            } else {
                // Fallback to PNG if JPEG conversion fails
                screenshotAttachment = AgentMessage.ImageAttachment(
                    data: pngData,
                    mimeType: "image/png",
                    fileName: "page-screenshot.png",
                )
            }
        } catch {
            Logger.error("Screenshot failed: \(error)", category: Logger.agent)
        }

        // Run native page content extraction
        let extractionResult: String
        do {
            guard let url = page.url else {
                throw PageContentExtractor.ExtractionError.nativeExtractionFailed
            }

            let tree = try await PageContentExtractor.extract(
                from: page.backingWebView,
                url: url,
                title: page.title,
            )
            let formatted = PageContentFormatter.format(tree)
            extractionResult = """
            ## Extracted Page Structure (Native)
            
            \(formatted)
            """
        } catch {
            extractionResult = "Extraction failed: \(error.localizedDescription)"
        }

        let prompt = """
        I've extracted the structure of the current page. Here's a screenshot of the page \
        and the extracted representation below. Please evaluate how well the extraction \
        captures the page content — what's captured well, what's missing, and what's \
        misidentified.
        
        \(extractionResult)
        """

        if let attachment = screenshotAttachment {
            pendingAttachments.append(attachment)
        }
        await sendMessage(prompt)
    }

    /// Loads chat history from the gateway.
    func loadHistory() async {
        guard connectionState.isConnected else { return }

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let history = try await client.fetchChatHistory(sessionKey: sessionKey)
            hasLoadedHistory = true

            // Convert history messages off the main actor to avoid blocking UI
            let historyMessages = await Task.detached(priority: .userInitiated) {
                history.messages.map { AgentMessage(from: $0) }
            }.value

            // Replace messages with history
            messages = historyMessages

            Logger.info("Loaded \(historyMessages.count) messages from history", category: Logger.agent)
        } catch {
            Logger.error("Failed to load history: \(error.localizedDescription)", category: Logger.agent)
            // Don't show error for history loading failure, just log it
        }
    }

    /// Clears the conversation and starts fresh.
    func clearConversation() async {
        // Abort any active streaming
        if isStreaming {
            await abortResponse()
        }

        messages.removeAll()
        streamingMessage = nil
        currentRunId = nil
        pendingAttachments.removeAll()
        error = nil
        thoughtStreamStore?.clear()

        await client.clearConversation()
    }

    /// Clears the current error.
    func clearError() {
        error = nil
    }

    /// Refreshes the HTTP endpoint availability status.
    func refreshHTTPEndpointStatus() async {
        await client.checkHTTPEndpointAvailability()
    }

    /// Enables the HTTP endpoint for large attachment support.
    ///
    /// Delegates to the client implementation, which handles the
    /// runtime-specific configuration details.
    ///
    /// - Returns: `true` if the endpoint was successfully enabled.
    @discardableResult
    func enableHTTPEndpoint() async -> Bool {
        await client.enableHTTPEndpoint()
    }

    /// Retries sending a failed message.
    func retryMessage(_ messageId: UUID) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              messages[index].sendFailed else {
            return
        }

        // Remove the failed message and re-send with the same content
        let failedMessage = messages.remove(at: index)
        let userMessage = AgentMessage.user(
            text: failedMessage.textContent,
            attachments: failedMessage.imageAttachments,
        )
        messages.append(userMessage)

        await performSend(userMessage: userMessage, messageText: failedMessage.textContent)
    }

    /// Performs the actual send operation for a user message.
    private func performSend(userMessage: AgentMessage, messageText: String) async {
        // Clear thoughts from the previous interaction
        thoughtStreamStore?.clear()

        let protocolAttachments = userMessage.imageAttachments.map { attachment in
            ChatSendParams.ChatAttachment(
                type: "image",
                mimeType: attachment.mimeType,
                fileName: attachment.fileName,
                content: attachment.base64Content,
            )
        }

        do {
            isStreaming = true
            currentRunId = try await sendWithRetry(
                messageText: messageText,
                attachments: protocolAttachments.isEmpty ? nil : protocolAttachments,
            )
            streamingMessage = AgentMessage.streamingAssistant(runId: currentRunId!)
        } catch {
            Logger.error("Failed to send message: \(error.localizedDescription)", category: Logger.agent)
            isStreaming = false
            currentRunId = nil

            if let idx = messages.lastIndex(where: { $0.id == userMessage.id }) {
                messages[idx].sendFailed = true
                messages[idx].sendError = error.localizedDescription
            }

            self.error = ChatError(
                message: "Failed to send: \(error.localizedDescription)",
                isRecoverable: true,
            )
        }
    }

    /// Sends a message with a single retry if the tool system hasn't finished configuring.
    ///
    /// `configureToolSystem` runs in a fire-and-forget `Task` after init. If the user
    /// sends a message before it completes (~3 actor hops, sub-millisecond typical),
    /// Claude Direct throws `.notConfigured`. Rather than surfacing an error, we wait
    /// briefly and retry once — the config will have completed by then.
    private func sendWithRetry(
        messageText: String,
        attachments: [ChatSendParams.ChatAttachment]?,
    ) async throws -> String {
        do {
            return try await client.sendChatMessage(
                sessionKey: sessionKey,
                message: messageText,
                attachments: attachments,
            )
        } catch ClaudeDirectClient.ClientError.notConfigured {
            try? await Task.sleep(for: .milliseconds(100))
            return try await client.sendChatMessage(
                sessionKey: sessionKey,
                message: messageText,
                attachments: attachments,
            )
        }
    }

    // MARK: - Attachment Management

    /// Adds an image attachment.
    ///
    /// Large images are automatically compressed to fit within the gateway payload limit.
    ///
    /// - Parameters:
    ///   - imageData: The raw image data.
    ///   - mimeType: The MIME type (e.g., "image/png").
    ///   - fileName: Optional file name.
    /// - Returns: `true` if the attachment was added.
    @discardableResult
    func addAttachment(imageData: Data, mimeType: String, fileName: String? = nil) -> Bool {
        // Check total size limit
        let currentSize = pendingAttachments.reduce(0) { $0 + $1.sizeBytes }
        Logger.info("[Agent] Adding attachment: mimeType=\(mimeType), size=\(imageData.count) bytes, fileName=\(fileName ?? "nil"), currentTotal=\(currentSize) bytes", category: Logger.agent)

        // Compress image if it exceeds the per-image limit
        var finalData = imageData
        var finalMimeType = mimeType

        if imageData.count > AgentChatConstants.maxImageBytes {
            Logger.info("[Agent] Image exceeds \(AgentChatConstants.maxImageBytes) bytes, compressing...", category: Logger.agent)
            if let compressed = compressImage(data: imageData, targetBytes: AgentChatConstants.maxImageBytes) {
                finalData = compressed
                finalMimeType = "image/jpeg"
                Logger.info("[Agent] Image compressed: \(imageData.count) -> \(compressed.count) bytes", category: Logger.agent)
            } else {
                Logger.warning("[Agent] Image compression failed, using original", category: Logger.agent)
            }
        }

        if currentSize + finalData.count > AgentChatConstants.maxAttachmentBytes {
            Logger.warning("[Agent] Attachment rejected: exceeds 5MB limit (current=\(currentSize), new=\(finalData.count))", category: Logger.agent)
            error = ChatError(
                message: "Attachments exceed 5MB limit",
                isRecoverable: true,
            )
            return false
        }

        let attachment = AgentMessage.ImageAttachment(
            data: finalData,
            mimeType: finalMimeType,
            fileName: fileName,
        )
        pendingAttachments.append(attachment)
        Logger.info("[Agent] Attachment added successfully: id=\(attachment.id), size=\(finalData.count) bytes, total pending=\(pendingAttachments.count)", category: Logger.agent)
        return true
    }

    /// Compresses an image to fit within target byte size.
    ///
    /// Strategy: First tries high quality at various resolutions, then reduces quality progressively.
    /// This preserves image clarity at the expense of resolution, which is usually acceptable.
    private func compressImage(data: Data, targetBytes: Int) -> Data? {
        guard let image = NSImage(data: data) else { return nil }

        // Get the best representation
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let originalWidth = CGFloat(bitmap.pixelsWide)
        let originalHeight = CGFloat(bitmap.pixelsHigh)

        // Start with high quality, progressively reduce if needed
        // Prefer reducing resolution over quality (images stay sharper)
        let qualityLevels: [CGFloat] = [0.85, 0.75, 0.65, 0.5]

        // Calculate max dimension based on target size (rough heuristic)
        // A 1920x1080 image at 80% JPEG quality is typically ~300-400KB
        let maxDimensions: [CGFloat] = [1_920, 1_600, 1_280, 1_024, 800, 640]

        for maxDim in maxDimensions {
            // Calculate scale to fit within max dimension
            let scale: CGFloat = if originalWidth > originalHeight {
                originalWidth > maxDim ? maxDim / originalWidth : 1.0
            } else {
                originalHeight > maxDim ? maxDim / originalHeight : 1.0
            }

            let newWidth = originalWidth * scale
            let newHeight = originalHeight * scale

            // Only resize if we're actually making it smaller
            let currentBitmap: NSBitmapImageRep
            if scale < 0.99 {
                guard let resized = resizeImage(bitmap: bitmap, to: NSSize(width: newWidth, height: newHeight)) else {
                    continue
                }
                currentBitmap = resized
            } else {
                currentBitmap = bitmap
            }

            // Try each quality level at this resolution
            for quality in qualityLevels {
                let properties: [NSBitmapImageRep.PropertyKey: Any] = [
                    .compressionFactor: quality,
                ]

                if let jpegData = currentBitmap.representation(using: .jpeg, properties: properties),
                   jpegData.count <= targetBytes {
                    Logger.info("[Agent] Compressed image: \(Int(originalWidth))x\(Int(originalHeight)) -> \(Int(newWidth))x\(Int(newHeight)) at quality \(quality)", category: Logger.agent)
                    return jpegData
                }
            }
        }

        // Last resort: aggressive compression at small size
        Logger.warning("[Agent] Using aggressive compression fallback", category: Logger.agent)
        if let smallBitmap = resizeImage(bitmap: bitmap, to: NSSize(width: 512, height: 512 * originalHeight / originalWidth)),
           let jpegData = smallBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.4]) {
            return jpegData
        }

        return nil
    }

    /// Resizes a bitmap to the specified size.
    private func resizeImage(bitmap: NSBitmapImageRep, to size: NSSize) -> NSBitmapImageRep? {
        guard let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: bitmap.bitsPerSample,
            samplesPerPixel: bitmap.samplesPerPixel,
            hasAlpha: bitmap.hasAlpha,
            isPlanar: bitmap.isPlanar,
            colorSpaceName: bitmap.colorSpaceName,
            bytesPerRow: 0,
            bitsPerPixel: 0,
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        NSGraphicsContext.current?.imageInterpolation = .high

        let targetRect = NSRect(origin: .zero, size: size)
        let sourceRect = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        bitmap.draw(in: targetRect, from: sourceRect, operation: .copy, fraction: 1.0, respectFlipped: true, hints: nil)

        NSGraphicsContext.restoreGraphicsState()

        return resized
    }

    /// Removes a pending attachment.
    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Clears all pending attachments.
    func clearAttachments() {
        pendingAttachments.removeAll()
    }

    // MARK: - Event Handling

    private func handleChatEvent(_ payload: ChatEventPayload) {
        switch payload.state {
        case .delta:
            handleDeltaEvent(payload)
        case .final:
            handleFinalEvent(payload)
        case .aborted:
            handleAbortedEvent(payload)
        case .error:
            handleErrorEvent(payload)
        }
    }

    private func handleDeltaEvent(_ payload: ChatEventPayload) {
        guard payload.runId == currentRunId else { return }

        if streamingMessage == nil {
            streamingMessage = AgentMessage.streamingAssistant(runId: payload.runId)
            // First delta: emit a planning thought
            thoughtStreamStore?.addThought(type: .plan, text: "Thinking...")
            streamingMessage?.update(from: payload)
            if let streaming = streamingMessage {
                messages.append(streaming)
            }
            return
        }

        streamingMessage?.update(from: payload)

        // Debounce subsequent updates to avoid too many UI refreshes
        pendingStreamingUpdate = streamingMessage
        scheduleStreamingUIUpdate()
    }

    /// Schedules a debounced UI update for streaming content.
    private func scheduleStreamingUIUpdate() {
        // Cancel existing debounce task
        streamingDebounceTask?.cancel()

        streamingDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: AgentChatConstants.streamingDebounceInterval)

            guard !Task.isCancelled, let self else { return }

            // Apply pending update
            if let pending = pendingStreamingUpdate {
                if let index = messages.lastIndex(where: { $0.runId == pending.runId }) {
                    messages[index] = pending
                }
                pendingStreamingUpdate = nil
            }
        }
    }

    private func handleFinalEvent(_ payload: ChatEventPayload) {
        guard payload.runId == currentRunId else { return }

        // Finalize any streaming thought
        thoughtStreamStore?.finalizeStreaming()

        // Cancel any pending debounced update
        streamingDebounceTask?.cancel()
        pendingStreamingUpdate = nil

        if var streaming = streamingMessage {
            // Update existing streaming message
            streaming.update(from: payload)

            // Check if message has content - if empty, show error instead
            if streaming.isEmpty {
                messages.removeAll { $0.runId == payload.runId }
                error = ChatError(
                    message: "Response was empty. The AI service may be unavailable.",
                    isRecoverable: true,
                )
            } else if let index = messages.lastIndex(where: { $0.runId == payload.runId }) {
                messages[index] = streaming
            } else {
                messages.append(streaming)
            }
        } else {
            // Final event without preceding deltas - create message from payload
            var message = AgentMessage.streamingAssistant(runId: payload.runId)
            message.update(from: payload)

            if message.isEmpty {
                // Empty response - show error
                error = ChatError(
                    message: "Response was empty. The AI service may be unavailable.",
                    isRecoverable: true,
                )
            } else {
                messages.append(message)
            }
        }

        isStreaming = false
        streamingMessage = nil
        currentRunId = nil
    }

    private func handleAbortedEvent(_ payload: ChatEventPayload) {
        guard payload.runId == currentRunId else { return }

        if let streaming = streamingMessage, !streaming.isEmpty {
            // Keep partial message with aborted indicator
            var finalMessage = streaming
            finalMessage.stopReason = "aborted"
            if let index = messages.lastIndex(where: { $0.runId == payload.runId }) {
                messages[index] = finalMessage
            }
        } else {
            // Remove empty streaming message
            messages.removeAll { $0.runId == payload.runId }
        }

        isStreaming = false
        streamingMessage = nil
        currentRunId = nil
    }

    private func handleErrorEvent(_ payload: ChatEventPayload) {
        guard payload.runId == currentRunId else { return }

        // Remove streaming message
        messages.removeAll { $0.runId == payload.runId }

        isStreaming = false
        streamingMessage = nil
        currentRunId = nil

        error = ChatError(
            message: payload.errorMessage ?? "An error occurred",
            isRecoverable: true,
        )
    }

    private func handleConnectionStateChange(_ state: AgentConnectionState) {
        connectionState = state
    }

    // MARK: - Context Building

    /// Builds the final message text, optionally prepending browser context.
    private func buildMessage(_ text: String, includingContext context: BrowserContext?) -> String {
        guard let context, settings.agentAutoIncludeContext else {
            return text
        }

        var contextParts: [String] = []

        if let url = context.url {
            contextParts.append("Current page: \(url)")
        }

        if let title = context.title, !title.isEmpty {
            contextParts.append("Title: \(title)")
        }

        if let selection = context.selectedText, !selection.isEmpty {
            contextParts.append("Selected text: \"\(selection)\"")
        }

        if let space = context.spaceName {
            contextParts.append("Space: \(space)")
        }

        if contextParts.isEmpty {
            return text
        }

        let contextBlock = contextParts.joined(separator: "\n")
        return """
        [Browser Context]
        \(contextBlock)
        
        [User Message]
        \(text)
        """
    }
}

// MARK: - Browser Context

/// Context from the browser to include with messages.
nonisolated struct BrowserContext: Sendable {
    let url: String?
    let title: String?
    let selectedText: String?
    let spaceName: String?
}

// MARK: - Convenience Initializer

extension AgentChatManager {
    /// Creates a chat manager using the factory to create the appropriate client.
    convenience init(settings: BrowserSettings) {
        let client = AgentClientFactory.makeClient(settings: settings)
        self.init(settings: settings, client: client)
    }
}

// MARK: - Preview Helpers

#if DEBUG
    extension AgentChatManager {
        /// Sets the manager's state directly for preview purposes.
        ///
        /// This bypasses the normal client/event flow and sets observable state directly.
        /// Only available in DEBUG builds.
        func setPreviewState(
            messages: [AgentMessage] = [],
            connectionState: AgentConnectionState = .connected,
            isStreaming: Bool = false,
            isLoadingHistory: Bool = false,
            pendingAttachments: [AgentMessage.ImageAttachment] = [],
            error: ChatError? = nil,
        ) {
            self.messages = messages
            self.connectionState = connectionState
            self.isStreaming = isStreaming
            self.isLoadingHistory = isLoadingHistory
            self.pendingAttachments = pendingAttachments
            self.error = error
        }
    }
#endif

// MARK: - AgentConnectionState UI Properties

extension AgentConnectionState {
    var statusText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case let .reconnecting(attempt): "Reconnecting (\(attempt))..."
        }
    }

    var dotColor: Color {
        switch self {
        case .connected: .green
        case .connecting, .reconnecting: .yellow
        case .disconnected: .red
        }
    }
}
