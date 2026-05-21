import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Constants

    enum DragConstants {
        static let dropZoneThresholdOffset: CGFloat = 20
        static let dropZoneTransitionDistance: CGFloat = 20
        static let groupHoverTolerance: CGFloat = 4
        static let groupBoundsTolerance: CGFloat = 8
    }

    /// Constants for drop zone placeholder sizing and positioning.
    ///
    /// These values are derived from the visual design:
    /// - Favorites drop zone uses a 1.5x height tile (54pt)
    /// - Pinned drop zone uses standard tab height (36pt)
    /// - Each placeholder has 16pt total vertical padding (8pt top + 8pt bottom)
    enum DropZoneConstants {
        /// Height of the favorites tile content (1.5x tab height)
        static let favoritesTileHeight: CGFloat = Constants.Layout.tabItemHeight * 1.5 // 54

        /// Height of the pinned placeholder content (standard tab height)
        static let pinnedPlaceholderHeight: CGFloat = Constants.Layout.tabItemHeight // 36

        /// Total vertical padding around drop zone placeholders (8pt top + 8pt bottom)
        static let verticalPadding: CGFloat = 8

        /// Total height of favorites drop zone including padding
        static let favoritesDropZoneTotalHeight: CGFloat = favoritesTileHeight + verticalPadding // 62

        /// Total height of pinned drop zone including padding
        static let pinnedDropZoneTotalHeight: CGFloat = pinnedPlaceholderHeight + verticalPadding // 44

        /// Offset for address bar push when favorites drop zone appears
        static let addressBarOffset: CGFloat = 32
    }
}
