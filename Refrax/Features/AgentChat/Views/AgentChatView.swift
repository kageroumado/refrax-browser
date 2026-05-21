import SwiftUI

/// Main container view for agent chat in the reference pane.
///
/// Provides:
/// - Message list with scrolling
/// - Input field with attachments
/// - Connection status indicator
/// - Empty state for first-time users
/// - Error handling with alerts
struct AgentChatView: View {
    @Environment(AgentChatManager.self) private var chatManager
    @Environment(BrowserSettings.self) private var settings
    @State private var showAgentConfig = false

    private var needsCredentialSetup: Bool {
        switch settings.agentProviderKind {
        case .claudeAPI, .openAI, .openRouter:
            !AgentCredentialStore.hasAPIKey(for: settings.agentProviderKind)
        case .custom:
            // Custom endpoints can legitimately be unauthenticated (local servers);
            // setup is "complete" as soon as a base URL + model are configured.
            settings.agentCustomBaseURL.isEmpty || settings.agentCustomModel.isEmpty
        }
    }

    var body: some View {
        Group {
            if needsCredentialSetup {
                AgentSetupView {
                    Task { await chatManager.connect() }
                }
            } else if chatManager.isLoadingHistory || chatManager.connectionState == .connecting {
                loadingState
            } else if chatManager.messages.isEmpty, !chatManager.isStreaming {
                emptyState
            } else {
                AgentMessageListView(
                    messages: chatManager.displayMessages,
                    isStreaming: chatManager.isStreaming,
                ) { messageId in
                    Task {
                        await chatManager.retryMessage(messageId)
                    }
                }
                .overlay(alignment: .top) {
                    if chatManager.isStreaming {
                        AgentThoughtStream()
                            .frame(maxHeight: 120)
                            .glassEffect(.regular, in: .rect(cornerRadius: 10))
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: chatManager.isStreaming)
            }
        }
        .safeAreaBar(edge: .top) { header }
        .safeAreaBar(edge: .bottom) {
            if !needsCredentialSetup {
                AgentChatInputView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !needsCredentialSetup else { return }
            await chatManager.connect()
        }
        .alert(
            "Chat Error",
            isPresented: .init(
                get: { chatManager.error != nil },
                set: { if !$0 { chatManager.clearError() } },
            ),
        ) {
            Button("OK") {
                chatManager.clearError()
            }
            if chatManager.error?.isRecoverable == true {
                Button("Retry") {
                    chatManager.clearError()
                    Task {
                        await chatManager.connect()
                    }
                }
            }
        } message: {
            if let error = chatManager.error {
                Text(error.message)
            }
        }
        .sheet(isPresented: $showAgentConfig) {
            AgentConfigSheet()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()

            Button {
                showAgentConfig = true
            } label: {
                ZStack(alignment: .top) {
                    // Name pill (behind avatar)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(chatManager.connectionState.dotColor)
                            .frame(width: 8, height: 8)

                        Text(settings.agentDisplayName)
                            .font(.callout.weight(.medium))

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .padding(.top, 34) // Position below avatar with slight overlap

                    // Avatar (on top)
                    agentAvatar
                        .frame(width: 42, height: 42)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agent-chat-header")

            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            if !chatManager.messages.isEmpty {
                Button {
                    Task { await chatManager.clearConversation() }
                } label: {
                    Image(systemName: "plus.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Conversation")
                .accessibilityIdentifier("agent-chat-new-conversation")
                .padding(.trailing, 8)
                .padding(.top, 6)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var agentAvatar: some View {
        if let avatarData = settings.agentAvatarData,
           let nsImage = NSImage(data: avatarData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()

            Text("Loading conversation...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple.opacity(0.6))

            // Title
            Text("Agent Chat")
                .font(.title2)
                .foregroundStyle(.primary)

            // Description
            Text("Ask about this page, research topics,\nor just have a conversation.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Quick actions
            VStack(spacing: 8) {
                quickActionButton(
                    "Summarize this page",
                    icon: "doc.text",
                    message: "Summarize this page for me.",
                )
                quickActionButton(
                    "What's the main topic?",
                    icon: "questionmark.circle",
                    message: "What's the main topic of this page?",
                )
                quickActionButton(
                    "Find similar content",
                    icon: "magnifyingglass",
                    message: "Can you help me find similar content to this page?",
                )
            }

            // Keyboard hint
            Text("Tip: ⌘⌃S to toggle chat")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickActionButton(
        _ title: String,
        icon: String,
        message: String,
    ) -> some View {
        Button {
            Task {
                await chatManager.sendMessage(message)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.bordered)
        .disabled(!chatManager.connectionState.isConnected)
        .accessibilityIdentifier("agent-chat-quick-\(title.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "?", with: "").replacingOccurrences(of: "'", with: ""))")
    }
}

// MARK: - Previews

#Preview("Empty State", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatView()
        .frame(width: 400, height: 600)
}

#Preview("With Messages", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatPreviewWrapper(
        messages: [
            .user(text: "What's on this page?"),
            .assistant(text: "This page appears to be about SwiftUI development. It covers topics like view composition, state management, and the declarative UI paradigm that Apple introduced with SwiftUI."),
            .user(text: "Can you summarize the key points?"),
            .assistant(text: "Sure! Here are the key points:\n\n1. **Declarative Syntax** - You describe what you want, not how to achieve it\n2. **State Management** - Use @State, @Binding, and @Observable for reactive updates\n3. **Composition** - Build complex UIs from small, reusable views\n4. **Platform Integration** - Works seamlessly with UIKit/AppKit"),
        ],
    )
    .frame(width: 400, height: 600)
}

#Preview("Streaming", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatPreviewWrapper(
        messages: [
            .user(text: "Explain quantum computing"),
            .assistant(text: "Quantum computing is a fascinating field that..."),
        ],
        isStreaming: true,
    )
    .frame(width: 400, height: 600)
}

#Preview("Connection Error", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatPreviewWrapper(
        connectionState: .disconnected,
        error: .init(message: "Failed to connect to gateway", isRecoverable: true),
    )
    .frame(width: 400, height: 600)
}

#Preview("Reconnecting", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatPreviewWrapper(
        messages: [
            .user(text: "Hello!"),
        ],
        connectionState: .reconnecting(attempt: 2),
    )
    .frame(width: 400, height: 600)
}

#Preview("Loading History", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatPreviewWrapper(isLoadingHistory: true)
        .frame(width: 400, height: 600)
}

// MARK: - Preview Wrapper

/// Wrapper view that configures the chat manager with preview state.
private struct AgentChatPreviewWrapper: View {
    @Environment(AgentChatManager.self) private var chatManager

    let messages: [AgentMessage]
    let connectionState: AgentConnectionState
    let isStreaming: Bool
    let error: AgentChatManager.ChatError?
    let isLoadingHistory: Bool

    init(
        messages: [AgentMessage] = [],
        connectionState: AgentConnectionState = .connected,
        isStreaming: Bool = false,
        error: AgentChatManager.ChatError? = nil,
        isLoadingHistory: Bool = false,
    ) {
        self.messages = messages
        self.connectionState = connectionState
        self.isStreaming = isStreaming
        self.error = error
        self.isLoadingHistory = isLoadingHistory
    }

    var body: some View {
        AgentChatView()
            .task {
                #if DEBUG
                    chatManager.setPreviewState(
                        messages: messages,
                        connectionState: connectionState,
                        isStreaming: isStreaming,
                        isLoadingHistory: isLoadingHistory,
                        error: error,
                    )
                #endif
            }
    }
}
