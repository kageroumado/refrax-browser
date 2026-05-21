import SwiftUI

// MARK: - Hover Fill Action Modifier

/// A view modifier that shows a progress fill animation on hover and triggers an action after a delay.
///
/// When the user hovers over the view, a fill animation progresses from left to right
/// over the specified duration. If the hover is maintained until completion, the action
/// is triggered. If the user stops hovering before completion, the animation resets.
///
/// While `isActive` is true (e.g., popover is shown), the fill stays at 100% and new
/// hovers are ignored. The fill resets when `isActive` becomes false and hover ends.
///
/// This is useful for buttons that show popovers on hover - the fill provides visual
/// feedback about the delay before the popover appears.
struct HoverFillActionModifier<ClipShape: Shape>: ViewModifier {
    @Binding var isActive: Bool
    let delay: Duration
    let fillColor: Color
    let clipShape: ClipShape
    let size: CGFloat
    let onComplete: () -> Void

    @State private var isHovering = false
    @State private var fillProgress: CGFloat = 0
    @State private var hoverTask: Task<Void, Never>?

    private var animationDuration: Double {
        Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(width: size * fillProgress, height: size)
                    .frame(width: size, alignment: .leading)
                    .clipShape(clipShape)
            }
            .onHover { hovering in
                handleHover(hovering)
            }
            .onChange(of: isActive) { _, active in
                if !active, !isHovering {
                    // Popover dismissed and not hovering - reset fill
                    withAnimation(.easeOut(duration: 0.15)) {
                        fillProgress = 0
                    }
                }
            }
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering

        // Ignore hover changes while popover is active
        guard !isActive else { return }

        if hovering {
            // Start fill animation and timer
            withAnimation(.linear(duration: animationDuration)) {
                fillProgress = 1
            }

            hoverTask = Task {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, isHovering else { return }
                onComplete()
            }
        } else {
            // Cancel and reset
            hoverTask?.cancel()
            hoverTask = nil

            withAnimation(.easeOut(duration: 0.15)) {
                fillProgress = 0
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds hover fill animation that triggers an action after a delay.
    ///
    /// Shows a fill animation from left to right during the hover delay. If hover
    /// is maintained until completion, the action is called. While `isActive` is true,
    /// the fill stays at 100% and new hovers are ignored.
    ///
    /// The fill is a rounded rectangle (corner radius 2) clipped to the provided shape.
    ///
    /// - Parameters:
    ///   - isActive: Binding indicating if the triggered state is active (e.g., popover shown).
    ///   - delay: Duration to wait before triggering action. Default is 500ms.
    ///   - fillColor: Color for the progress fill animation.
    ///   - clipShape: Shape for clipping the fill animation.
    ///   - size: Fixed size for the fill animation (width and height).
    ///   - action: Action to perform when hover delay completes.
    func hoverFillAction(
        isActive: Binding<Bool>,
        delay: Duration = .milliseconds(500),
        fillColor: Color = .secondary.opacity(0.2),
        clipShape: some Shape,
        size: CGFloat,
        action: @escaping () -> Void,
    ) -> some View {
        modifier(HoverFillActionModifier(
            isActive: isActive,
            delay: delay,
            fillColor: fillColor,
            clipShape: clipShape,
            size: size,
            onComplete: action,
        ))
    }
}
