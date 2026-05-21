import SwiftUI

/// iMessage-style bubble view for a single agent message.
///
/// Renders user messages with blue bubbles (right-aligned) and assistant
/// messages with gray glass bubbles (left-aligned). Supports text content,
/// image attachments, and code blocks.
///
/// When `isStreamingMessage` is true, text is revealed progressively at
/// ~60 chars/sec (typewriter effect) for a natural streaming feel.
struct AgentMessageView: View {
    let message: AgentMessage
    var isStreamingMessage: Bool = false
    var onRetry: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    @State private var isToolsExpanded = false

    // MARK: - Typewriter State

    /// How many characters are currently visible. `Int.max` means fully revealed
    /// (the default for non-streaming messages).
    @State private var revealedCount = Int.max

    /// The running reveal animation task.
    @State private var revealTask: Task<Void, Never>?

    /// Maximum characters to show before truncating.
    private static let truncationThreshold = 600

    /// Characters revealed per animation tick.
    private static let revealCharsPerTick = 2

    /// Animation tick interval (~30 fps).
    private static let revealTickInterval: Duration = .milliseconds(33)

    private var isUser: Bool {
        message.role == .user
    }

    /// Whether the typewriter animation is still in progress.
    private var isRevealing: Bool {
        isStreamingMessage || revealedCount < message.textContent.count
    }

    private var shouldTruncate: Bool {
        !isExpanded && message.textContent.count > Self.truncationThreshold
    }

    private var displayContent: String {
        if isRevealing {
            return String(message.textContent.prefix(revealedCount))
        }
        if shouldTruncate {
            let index = message.textContent.index(
                message.textContent.startIndex,
                offsetBy: Self.truncationThreshold,
            )
            return String(message.textContent[..<index]) + "…"
        }
        return message.textContent
    }

    private var bubbleColor: Color {
        if isUser {
            Color.appAccentColor
        } else {
            colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.05)
        }
    }

    private var textColor: Color {
        isUser ? .white : .primary
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)

                // Failed indicator (before bubble for user messages)
                if message.sendFailed {
                    failedIndicator
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                // Image attachments
                if !message.imageAttachments.isEmpty {
                    attachmentsView
                }

                // Tool use indicators (assistant messages only)
                if !isUser, message.hasToolContent {
                    toolIndicatorsView
                }

                // Text content
                if !message.textContent.isEmpty {
                    textBubble
                }
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 12)
        .onAppear {
            if isStreamingMessage, revealedCount == Int.max {
                revealedCount = 0
                if !message.textContent.isEmpty {
                    startRevealLoop(targetCount: message.textContent.count)
                }
            }
        }
        .onChange(of: message.textContent.count) { _, newCount in
            if revealedCount != Int.max, revealedCount < newCount {
                startRevealLoop(targetCount: newCount)
            }
        }
        .onDisappear {
            revealTask?.cancel()
        }
    }

    // MARK: - Typewriter Animation

    /// Starts (or restarts) the reveal loop targeting `targetCount` characters.
    ///
    /// Cancels any existing loop so the new one inherits the updated target.
    /// The loop reads/writes `revealedCount` (@State) which persists across
    /// view updates, ensuring smooth reveal even as the underlying message changes.
    private func startRevealLoop(targetCount: Int) {
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            while !Task.isCancelled, revealedCount < targetCount {
                try? await Task.sleep(for: Self.revealTickInterval)
                guard !Task.isCancelled else { break }
                revealedCount = min(revealedCount + Self.revealCharsPerTick, targetCount)
            }
            revealTask = nil
        }
    }

    // MARK: - Failed Indicator

    private var failedIndicator: some View {
        Button {
            onRetry?()
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 20))
        }
        .buttonStyle(.plain)
        .help(message.sendError ?? "Tap to retry")
        .accessibilityLabel("Message failed to send. Tap to retry.")
    }

    // MARK: - Text Bubble

    private var textBubble: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            MarkdownContentView(content: displayContent, isUserMessage: isUser)

            if !isRevealing, message.textContent.count > Self.truncationThreshold {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "Show more")
                        .font(.caption)
                        .foregroundStyle(isUser ? .white.opacity(0.8) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .foregroundStyle(textColor)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 4,
                topTrailingRadius: 18,
            )
            .fill(bubbleColor)
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: 18,
                topTrailingRadius: 18,
            )
            .fill(bubbleColor)
        }
    }

    // MARK: - Tool Indicators

    @ViewBuilder
    private var toolIndicatorsView: some View {
        let toolBlocks = message.toolUseBlocks
        let resultBlocks = message.toolResultBlocks

        if !toolBlocks.isEmpty {
            ToolIndicatorsView(
                toolUses: toolBlocks,
                toolResults: resultBlocks,
                isExpanded: $isToolsExpanded,
            )
        }
    }

    // MARK: - Attachments

    private var attachmentsView: some View {
        HStack(spacing: 8) {
            ForEach(message.imageAttachments) { attachment in
                LazyImageAttachmentView(attachment: attachment)
            }
        }
    }
}

// MARK: - Lazy Image Attachment

/// View that lazily loads and displays an image attachment.
///
/// Shows a placeholder while the image is loading, then displays the decoded image.
/// Images are cached after first load for efficient re-rendering.
private struct LazyImageAttachmentView: View {
    let attachment: AgentMessage.ImageAttachment

    @State private var loadedImage: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = loadedImage {
                // Loaded image
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 200, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isLoading {
                // Loading placeholder
                placeholderView
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
            } else {
                // Not yet loaded
                placeholderView
            }
        }
        .task(id: attachment.id) {
            await loadImage()
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(width: 120, height: 90)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
            }
    }

    private func loadImage() async {
        // Skip if already loaded
        guard loadedImage == nil else { return }

        // For already-loaded attachments, decode directly
        if let data = attachment.data {
            loadedImage = NSImage(data: data)
            return
        }

        // For lazy attachments, use the cache
        isLoading = true
        loadedImage = await AgentImageCache.shared.image(for: attachment)
        isLoading = false
    }
}

// MARK: - Tool Indicators

/// Compact, collapsible view showing tool use during an agent response.
///
/// Collapsed: shows a single pill with tool count.
/// Expanded: shows each tool use with its result status.
private struct ToolIndicatorsView: View {
    let toolUses: [AgentMessage.ToolUseBlock]
    let toolResults: [AgentMessage.ToolResultBlock]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Summary pill (always shown)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                    Text(summaryText)
                        .font(.caption)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(toolUses, id: \.id) { toolUse in
                        toolUseRow(toolUse)
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var summaryText: String {
        let count = toolUses.count
        if count == 1 {
            return toolUses[0].displayName
        }
        return "\(count) tool calls"
    }

    @ViewBuilder
    private func toolUseRow(_ toolUse: AgentMessage.ToolUseBlock) -> some View {
        let result = toolResults.first { $0.toolUseId == toolUse.id }
        let hasError = result?.isError ?? false

        HStack(spacing: 4) {
            Image(systemName: hasError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(hasError ? .red : .green)

            Text(toolUse.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if hasError, let errorContent = result?.content {
                Text("— \(errorContent.prefix(60))")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    VStack(spacing: 16) {
        AgentMessageView(message: .user(text: "Can you show me how to use `async/await`?"))
        AgentMessageView(message: .assistant(text: """
        Sure! Here's a simple example:
        
        ```swift
        func fetchData() async throws -> Data {
            let url = URL(string: "https://api.example.com")!
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
        ```
        
        You can call it with `try await fetchData()`.
        
        **Key points:**
        - Use `async` to mark asynchronous functions
        - Use `await` to call them
        - Use `try` for throwing functions
        """))
        AgentMessageView(message: .user(text: "Thanks!"))
    }
    .padding()
    .frame(width: 400)
}
