import SwiftUI

/// Subtle connection status indicator for agent chat.
///
/// Shows a small dot with color indicating connection state:
/// - Green: Connected
/// - Yellow: Connecting/Reconnecting
/// - Red: Disconnected
struct AgentConnectionBadge: View {
    let state: AgentConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.dotColor)
                .frame(width: 8, height: 8)
                .overlay {
                    if state.isTransitioning {
                        Circle()
                            .stroke(state.dotColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                    }
                }

            Text(state.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Compact Variant

extension AgentConnectionBadge {
    /// A minimal variant showing only the dot.
    struct Compact: View {
        let state: AgentConnectionState

        var body: some View {
            Circle()
                .fill(state.dotColor)
                .frame(width: 8, height: 8)
                .help(state.statusText)
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    VStack(spacing: 16) {
        AgentConnectionBadge(state: .connected)
        AgentConnectionBadge(state: .connecting)
        AgentConnectionBadge(state: .reconnecting(attempt: 2))
        AgentConnectionBadge(state: .disconnected)
    }
    .padding()
}
