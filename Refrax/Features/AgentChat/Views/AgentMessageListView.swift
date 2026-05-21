import SwiftUI

/// Scrollable list of agent chat messages with timestamp grouping.
///
/// Automatically scrolls to new messages when at the bottom.
/// Groups messages with timestamps when there's a gap > 5 minutes.
struct AgentMessageListView: View {
    let messages: [AgentMessage]
    let isStreaming: Bool
    var onRetryMessage: ((UUID) -> Void)?

    @State private var scrolledToBottom = true
    @State private var showNewMessagePill = false

    /// Minimum gap between messages to show a timestamp (5 minutes).
    private static let timestampGapThreshold: TimeInterval = 5 * 60

    // MARK: - Display Item

    /// Categorizes how a message should be displayed.
    private enum DisplayItem: Identifiable {
        case bubble(AgentMessage)
        case heartbeatSkipped(AgentMessage)

        var id: UUID {
            switch self {
            case let .bubble(msg), let .heartbeatSkipped(msg):
                msg.id
            }
        }

        var message: AgentMessage {
            switch self {
            case let .bubble(msg), let .heartbeatSkipped(msg):
                msg
            }
        }
    }

    /// Categorizes pre-filtered messages for presentation.
    ///
    /// Messages are already filtered by the manager's `displayMessages` property.
    /// This only handles presentation categorization (bubble vs heartbeat indicator).
    private var displayItems: [DisplayItem] {
        messages.map { message in
            let trimmed = message.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "HEARTBEAT_OK" {
                return .heartbeatSkipped(message)
            }
            return .bubble(message)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 8) {
                            // Show timestamp if gap > 5 minutes
                            if shouldShowTimestamp(at: index, in: displayItems) {
                                timestampView(for: item.message.timestamp)
                            }

                            switch item {
                            case let .bubble(message):
                                let isStreamingMsg = isStreaming
                                    && message.role == .assistant
                                    && index == displayItems.count - 1
                                AgentMessageView(
                                    message: message,
                                    isStreamingMessage: isStreamingMsg,
                                ) {
                                    onRetryMessage?(message.id)
                                }
                                .id(message.id)

                            case let .heartbeatSkipped(message):
                                heartbeatSkippedView
                                    .id(message.id)
                            }
                        }
                    }

                    // Streaming indicator
                    if isStreaming {
                        AgentTypingIndicator()
                            .id("typing-indicator")
                    }

                    // Bottom anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let maxOffset = geometry.contentSize.height - geometry.containerSize.height
                return geometry.contentOffset.y >= maxOffset - 20
            } action: { _, isAtBottom in
                scrolledToBottom = isAtBottom
            }
            .onChange(of: messages.count) { oldCount, newCount in
                guard newCount > oldCount else { return }

                // When the user sends a message, they're necessarily at the bottom
                // of the conversation — always scroll to show their message.
                // For assistant messages, respect the tracked scroll position.
                // Note: scrolledToBottom may be stale here because adding content
                // causes onScrollGeometryChange to fire first (maxOffset increases
                // while viewport hasn't moved, making it appear "not at bottom").
                let userJustSent = messages.last?.role == .user
                if userJustSent || scrolledToBottom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    scrolledToBottom = true
                    showNewMessagePill = false
                } else {
                    showNewMessagePill = true
                }
            }
            .onChange(of: isStreaming) { _, _ in
                // Scroll on streaming end (response complete) or start (typing indicator).
                if scrolledToBottom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showNewMessagePill {
                    newMessagePill {
                        withAnimation(.spring(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                            showNewMessagePill = false
                            scrolledToBottom = true
                        }
                    }
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Timestamp Logic

    private func shouldShowTimestamp(at index: Int, in items: [DisplayItem]) -> Bool {
        guard index > 0 else {
            // Always show timestamp for first message
            return true
        }

        let currentMessage = items[index].message
        let previousMessage = items[index - 1].message

        let gap = currentMessage.timestamp.timeIntervalSince(previousMessage.timestamp)
        return gap > Self.timestampGapThreshold
    }

    private func timestampView(for date: Date) -> some View {
        Text(formatTimestamp(date))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    // MARK: - Heartbeat Skipped

    private var heartbeatSkippedView: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10))
            Text("Reply skipped")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }

        return formatter.string(from: date)
    }

    // MARK: - New Message Pill

    private func newMessagePill(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("New messages")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    AgentMessageListView(
        messages: [
            .user(text: "Hello!"),
            .assistant(text: "Hi there! How can I help you today?"),
            .user(text: "What's on this page?"),
            .assistant(text: "Based on what I can see, this appears to be a documentation page about SwiftUI views and their lifecycle."),
        ],
        isStreaming: false,
    )
    .frame(width: 400, height: 500)
}
