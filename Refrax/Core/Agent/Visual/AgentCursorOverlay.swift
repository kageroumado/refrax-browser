import SwiftUI

/// Container overlay that sits above web content to render agent visual feedback.
///
/// Hosts the `AgentCursor` and all `ElementHighlight` views. Positioned relative
/// to the web view's coordinate space and does NOT intercept mouse events,
/// allowing full passthrough to the underlying web content.
///
/// ## Coordinate System
///
/// The overlay occupies the same frame as the web view container. The
/// `VisualFeedbackManager` provides positions in this coordinate space.
/// Page-space to screen-space conversion should be performed before
/// passing coordinates to the manager (using `JavaScriptSnippets.visibleViewport`
/// for scroll offset and zoom level).
///
/// ## Usage
///
/// Place as an overlay on the web view container:
///
/// ```swift
/// WebView(page)
///     .overlay {
///         AgentCursorOverlay()
///     }
/// ```
struct AgentCursorOverlay: View {
    @Environment(VisualFeedbackManager.self) private var feedback

    var body: some View {
        ZStack {
            if feedback.isActive {
                // Element highlights layer (below cursor)
                ElementHighlightLayer(highlights: feedback.highlights)

                // Agent cursor (above highlights)
                AgentCursor(
                    state: feedback.cursorState,
                    position: feedback.cursorPosition,
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Agent Cursor Overlay") {
    let manager = VisualFeedbackManager()

    ZStack {
        // Simulated web content
        VStack(spacing: 0) {
            Rectangle().fill(.blue.opacity(0.1))
            Rectangle().fill(.green.opacity(0.1))
            Rectangle().fill(.orange.opacity(0.1))
        }

        AgentCursorOverlay()
    }
    .frame(width: 400, height: 300)
    .environment(manager)
    .task {
        manager.activate()
        manager.moveCursor(
            to: CGPoint(x: 200, y: 150),
            in: CGRect(x: 0, y: 0, width: 400, height: 300),
        )
        manager.highlightElement(
            rect: CGRect(x: 100, y: 80, width: 200, height: 40),
            style: .standard,
        )
    }
}
