import SwiftUI

/// Visual cursor representing the AI agent's focus on the page.
///
/// Renders differently based on the current `AgentCursorState`:
/// - **idle**: Subtle ring, accent color at 40% opacity
/// - **hovering**: Filled circle, accent color at 70%
/// - **clicking**: Pulse animation — scale up then down
/// - **reading**: Vertical scanning indicator
/// - **thinking**: Breathing/pulsing glow
///
/// ## Animation Strategy
///
/// Position animation uses an explicit `.animation()` modifier with spring dynamics
/// on the container, NOT `withAnimation`. This avoids the catastrophic 60fps
/// re-render problem described in CLAUDE.md's Observation section.
///
/// State transitions (idle -> hovering -> clicking) use SwiftUI's built-in
/// animatable properties (opacity, scaleEffect) with `.animation()` modifiers.
///
/// Continuous animations (reading, thinking) respect `accessibilityReduceMotion`
/// and fall back to static indicators when motion is reduced.
struct AgentCursor: View {
    let state: AgentCursorState
    let position: CGPoint

    /// Phase driver for continuous animations (thinking, reading).
    @State private var animationPhase: CGFloat = 0

    /// Click animation scale.
    @State private var clickScale: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Constants {
        static let idleSize: CGFloat = 12
        static let hoverSize: CGFloat = 14
        static let clickSize: CGFloat = 14
        static let readingWidth: CGFloat = 24
        static let readingHeight: CGFloat = 4
        static let thinkingSize: CGFloat = 14
        static let glowRadius: CGFloat = 8
    }

    var body: some View {
        cursorShape
            .position(position)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.8),
                value: position,
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Cursor Shapes

    @ViewBuilder
    private var cursorShape: some View {
        switch state {
        case .idle:
            idleCursor
        case .hovering:
            hoverCursor
        case .clicking:
            clickCursor
        case .reading:
            readingCursor
        case .thinking:
            thinkingCursor
        }
    }

    private var idleCursor: some View {
        Circle()
            .stroke(Color.appAccentColor.opacity(0.4), lineWidth: 2)
            .frame(width: Constants.idleSize, height: Constants.idleSize)
    }

    private var hoverCursor: some View {
        Circle()
            .fill(Color.appAccentColor.opacity(0.7))
            .frame(width: Constants.hoverSize, height: Constants.hoverSize)
            .shadow(color: Color.appAccentColor.opacity(0.3), radius: 4)
    }

    private var clickCursor: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(Color.appAccentColor.opacity(0.3), lineWidth: 2)
                .frame(width: Constants.clickSize * clickScale * 1.6, height: Constants.clickSize * clickScale * 1.6)

            // Inner filled circle
            Circle()
                .fill(Color.appAccentColor.opacity(0.8))
                .frame(width: Constants.clickSize, height: Constants.clickSize)
                .scaleEffect(clickScale)
        }
        .onAppear {
            clickScale = reduceMotion ? 1.0 : 1.3
        }
        .animation(.easeOut(duration: 0.15), value: clickScale)
    }

    private var readingCursor: some View {
        Capsule()
            .fill(Color.appAccentColor.opacity(0.5))
            .frame(width: Constants.readingWidth, height: Constants.readingHeight)
            .offset(y: reduceMotion ? 0 : animationPhase * 20)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    animationPhase = 1
                }
            }
            .onDisappear {
                animationPhase = 0
            }
    }

    private var thinkingCursor: some View {
        Circle()
            .fill(Color.appAccentColor.opacity(reduceMotion ? 0.5 : 0.3 + animationPhase * 0.4))
            .frame(
                width: Constants.thinkingSize + (reduceMotion ? 0 : animationPhase * 4),
                height: Constants.thinkingSize + (reduceMotion ? 0 : animationPhase * 4),
            )
            .shadow(
                color: Color.appAccentColor.opacity(reduceMotion ? 0.3 : 0.2 + animationPhase * 0.2),
                radius: reduceMotion ? Constants.glowRadius : Constants.glowRadius + animationPhase * 4,
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    animationPhase = 1
                }
            }
            .onDisappear {
                animationPhase = 0
            }
    }
}

// MARK: - Preview

#Preview("Cursor States") {
    VStack(spacing: 40) {
        ForEach(
            [
                ("Idle", AgentCursorState.idle),
                ("Hovering", AgentCursorState.hovering),
                ("Clicking", AgentCursorState.clicking),
                ("Reading", AgentCursorState.reading),
                ("Thinking", AgentCursorState.thinking),
            ],
            id: \.0,
        ) { label, state in
            VStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 80, height: 60)
                    AgentCursor(state: state, position: CGPoint(x: 40, y: 30))
                }
                .frame(width: 80, height: 60)
            }
        }
    }
    .padding()
}
