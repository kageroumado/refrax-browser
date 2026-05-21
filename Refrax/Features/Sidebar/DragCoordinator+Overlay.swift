import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Private Helpers - Overlay Frame

    func calculateCurrentOverlayFrame() -> CGRect {
        // Return zero rect if frames not yet captured
        guard let originalFrame = _draggedItemOriginalFrame else {
            return .zero
        }

        // For groups, use the group bounds with current offset
        if let groupBounds = _draggedGroupBounds {
            return CGRect(
                x: groupBounds.minX,
                y: groupBounds.minY + currentOffset,
                width: groupBounds.width,
                height: groupBounds.height,
            )
        }

        // For individual items, use the original frame with current offset
        return CGRect(
            x: originalFrame.minX,
            y: originalFrame.minY + currentOffset,
            width: originalFrame.width,
            height: Constants.Layout.tabItemHeight,
        )
    }

    // MARK: - Private Helpers - Easing

    func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
