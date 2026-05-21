import SwiftUI

/// Overlay view displaying a preview thumbnail of a hovered tab.
///
/// Positioned to the right of the hovered tab, vertically centered at its
/// position. Shows the tab's web content as a thumbnail with smooth fade-in
/// animation.
///
/// ## Architecture
///
/// This view is rendered in `OverlayContainer` which sits above all split view
/// content. It uses global (window) coordinates from `TabPreviewManager` to
/// position the preview correctly relative to the hovered tab.
///
/// The thumbnail is provided by `TabPreviewProvider` via `WebViewThumbnail`,
/// which wraps `_WKThumbnailView` for efficient WebKit rendering.
///
/// ## Usage
///
/// Add this overlay to OverlayContainer:
///
/// ```swift
/// ZStack(alignment: .topLeading) {
///     // ... other overlays
///     TabPreviewOverlay()
/// }
/// ```
struct TabPreviewOverlay: View {
    @Environment(TabPreviewManager.self) private var tabPreviewManager
    @Environment(WindowState.self) private var windowState

    // MARK: - Constants

    private enum Layout {
        static let previewWidth: CGFloat = 320
        static let previewHeight: CGFloat = 200
        static let cornerRadius: CGFloat = 12
        static let shadowRadius: CGFloat = 16
        static let horizontalOffset: CGFloat = 16
        static let animationDuration: Double = 0.2
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            if let hoveredTab = tabPreviewManager.hoveredTab,
               tabPreviewManager.isPreviewVisible {
                let tabFrame = tabPreviewManager.hoveredTabFrame

                previewCard(for: hoveredTab.id)
                    .position(
                        x: positionX(tabFrame: tabFrame, in: geometry.size),
                        y: clampedY(tabFrame.midY, in: geometry.size.height),
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: Layout.animationDuration), value: tabPreviewManager.isPreviewVisible)
    }

    // MARK: - Preview Card

    private func previewCard(for tabID: Tab.ID) -> some View {
        WebViewThumbnail(tabID: tabID, useCache: false)
            .frame(width: Layout.previewWidth, height: Layout.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.25), radius: Layout.shadowRadius, y: 4)
    }

    // MARK: - Positioning

    /// Calculates X position for the preview, to the right of the sidebar.
    private func positionX(tabFrame _: CGRect, in _: CGSize) -> CGFloat {
        let sidebarWidth = windowState.isSidebarCollapsed ? 0 : windowState.sidebarThickness
        return sidebarWidth + Layout.previewWidth / 2 + Layout.horizontalOffset
    }

    /// Clamps the Y position to keep the preview fully visible.
    private func clampedY(_ y: CGFloat, in height: CGFloat) -> CGFloat {
        let halfHeight = Layout.previewHeight / 2
        let minY = halfHeight + Constants.Spacing.medium
        let maxY = height - halfHeight - Constants.Spacing.medium

        return min(max(y, minY), maxY)
    }
}
