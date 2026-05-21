import SwiftUI

// MARK: - Compact Tab Title Overlay

/// Displays the tab title when hovering a compact tab button.
///
/// Positioned to the right of the tab button using global coordinates converted
/// to the overlay container's coordinate space. Appears after a hover delay
/// managed by CompactTabButton.
struct CompactTabTitleOverlay: View {
    @Environment(WindowState.self) private var windowState

    private enum Layout {
        static let horizontalOffset: CGFloat = 8
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
        static let fontSize: CGFloat = 12
        static let maxWidth: CGFloat = 300
    }

    var body: some View {
        GeometryReader { containerGeo in
            let containerOrigin = containerGeo.frame(in: .global).origin
            let buttonFrame = windowState.compactTabTooltipFrame

            // Only show tooltip if we have a valid frame (not zero) and title
            if let title = windowState.compactTabTooltipTitle,
               buttonFrame.width > 0, buttonFrame.height > 0 {
                let localX = buttonFrame.maxX - containerOrigin.x + Layout.horizontalOffset
                let localY = buttonFrame.midY - containerOrigin.y

                tooltipContent(title: title)
                    .fixedSize()
                    .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: localX, y: localY)
            }
        }
        .allowsHitTesting(false)
    }

    private func tooltipContent(title: String) -> some View {
        ViewThatFits(in: .horizontal) {
            titleText(title)
                .fixedSize(horizontal: true, vertical: false)

            titleText(title)
                .frame(maxWidth: Layout.maxWidth, alignment: .leading)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .clipShape(Capsule())
        .glassEffect(.regular, in: Capsule())
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Layout.fontSize))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
