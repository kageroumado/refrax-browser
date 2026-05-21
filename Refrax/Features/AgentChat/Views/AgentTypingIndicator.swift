import SwiftUI

/// Three animated dots indicating the assistant is typing.
///
/// Displays a bubble with three dots that bounce sequentially,
/// providing visual feedback during streaming responses.
struct AgentTypingIndicator: View {
    @State private var animationPhase = 0

    @Environment(\.colorScheme) private var colorScheme

    private var bubbleColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                        .offset(y: animationPhase == index ? -4 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                )
                .fill(bubbleColor),
            )

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 12)
        .task {
            while !Task.isCancelled {
                for phase in 0 ..< 3 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        animationPhase = phase
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    VStack {
        AgentTypingIndicator()
    }
    .frame(width: 300)
    .padding()
}
