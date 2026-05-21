import SwiftUI

/// Displays AI responses inline in the Command Lens.
///
/// Shows the AI response with markdown rendering, along with
/// action buttons for follow-up or transferring to Reference Pane.
struct CommandLensAIView: View {
    @Environment(CommandLensManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // AI Response content
            if manager.isAILoading {
                loadingView
            } else if let response = manager.aiResponse {
                responseView(response)
            } else if let error = manager.aiError {
                errorView(error)
            }

            // Action bar
            actionBar
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Loading State

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("Thinking...")
                .foregroundStyle(.secondary)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Response View

    private func responseView(_ response: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // AI icon indicator
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .font(.body.weight(.medium))

                Text("AI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if manager.isAIStreaming {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            MarkdownContentView(content: response, isUserMessage: false)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(error)
                .foregroundStyle(.secondary)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            // Follow-up input hint
            if manager.aiResponse != nil {
                Text("Type to follow up...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Transfer to Reference Pane button
            if manager.aiResponse != nil || manager.isAILoading {
                Button {
                    manager.transferToReferencePane()
                } label: {
                    HStack(spacing: 4) {
                        Text("Continue in Pane")
                            .font(.caption.weight(.medium))

                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    VStack {
        CommandLensAIView()
    }
    .frame(width: 600, height: 200)
    .padding()
}
