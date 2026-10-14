import CoreGraphics
import SwiftUI

/// The three shapes a floating card takes, chosen by its size: a favicon squircle, a tab of
/// favicon and title, and a live page under that tab's header.
nonisolated enum FloatingCardShape: String, Codable, CaseIterable, Sendable {
    case icon
    case tab
    case live

    /// The sizes, limits, and crossing thresholds of every shape.
    ///
    /// Each crossing has two thresholds, one per direction, set apart so a pointer resting near
    /// a boundary never flips the card back and forth. Every threshold sits past the limit of
    /// the shape the card leaves, so the card holds its shape for a stretch of pointer travel
    /// before it crosses: 52 pt from an icon to a tab, 48 pt from the narrowest tab to an icon,
    /// 76 pt from a tab to a live page, 80 pt from the shortest live page to a tab.
    enum Layout {
        /// The icon's side; the icon never changes size.
        static let iconSide: CGFloat = 44
        /// The favicon's side inside the icon.
        static let iconFaviconSize: CGFloat = 24

        static let tabHeight: CGFloat = FloatingTabPlacement.headerHeight
        static let tabMinimumWidth: CGFloat = 120
        static let tabMaximumWidth: CGFloat = 360
        static let tabNaturalWidth: CGFloat = 250

        static let liveMinimumSize = CGSize(width: 240, height: 160)
        static let liveNaturalSize = CGSize(width: 340, height: 250)

        /// An icon dragged wider than this becomes a tab.
        static let iconToTabWidth: CGFloat = 96
        /// A tab dragged narrower than this becomes an icon.
        static let tabToIconWidth: CGFloat = 72
        /// An icon or tab dragged taller than this becomes a live page.
        static let tabToLiveHeight: CGFloat = 110
        /// A live page dragged shorter than this becomes a tab, or an icon when it is also
        /// narrower than ``tabToIconWidth``.
        static let liveToTabHeight: CGFloat = 80

        /// The resize band along each edge, centered on it.
        static let resizeEdgeThickness: CGFloat = 8
        /// The resize square at each corner, centered on it.
        static let resizeCornerSide: CGFloat = 12
        /// How far past the card's edge its resize zones reach.
        static var resizeOutset: CGFloat {
            max(resizeEdgeThickness, resizeCornerSide) / 2
        }

        /// The shape change: a 0.2 s spring with no bounce, moving frame and radius together.
        static let shapeSpring = Animation.spring(duration: 0.2, bounce: 0)
        /// The shape change under Reduce Motion: the frame jumps and the content fades.
        static let reducedMotionFade = Animation.easeInOut(duration: 0.1)
    }

    /// The shape a card in `self` takes when its size is dragged to `proposed`.
    ///
    /// `proposed` is where the pointer puts the card's size before any shape limit applies.
    static func shape(after current: Self, proposing proposed: CGSize) -> Self {
        switch current {
        case .icon:
            if proposed.height > Layout.tabToLiveHeight {
                return .live
            }
            return proposed.width > Layout.iconToTabWidth ? .tab : .icon
        case .tab:
            if proposed.height > Layout.tabToLiveHeight {
                return .live
            }
            return proposed.width < Layout.tabToIconWidth ? .icon : .tab
        case .live:
            guard proposed.height < Layout.liveToTabHeight else { return .live }
            return proposed.width < Layout.tabToIconWidth ? .icon : .tab
        }
    }

    /// The smallest size this shape takes.
    var minimumSize: CGSize {
        switch self {
        case .icon: CGSize(width: Layout.iconSide, height: Layout.iconSide)
        case .tab: CGSize(width: Layout.tabMinimumWidth, height: Layout.tabHeight)
        case .live: Layout.liveMinimumSize
        }
    }

    /// The largest size this shape takes; a live page grows until the window stops it.
    var maximumSize: CGSize {
        switch self {
        case .icon: CGSize(width: Layout.iconSide, height: Layout.iconSide)
        case .tab: CGSize(width: Layout.tabMaximumWidth, height: Layout.tabHeight)
        case .live: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
    }

    /// The size a card of this shape has before anyone resizes it.
    var naturalSize: CGSize {
        switch self {
        case .icon: minimumSize
        case .tab: CGSize(width: Layout.tabNaturalWidth, height: Layout.tabHeight)
        case .live: Layout.liveNaturalSize
        }
    }

    /// The size of this shape closest to `size`; a dimension that is not finite takes the
    /// natural size's.
    func fitted(_ size: CGSize) -> CGSize {
        let natural = naturalSize
        let width = size.width.isFinite ? size.width : natural.width
        let height = size.height.isFinite ? size.height : natural.height
        return CGSize(
            width: min(max(width, minimumSize.width), maximumSize.width),
            height: min(max(height, minimumSize.height), maximumSize.height),
        )
    }

    /// The shape after this one in the header's cycle: icon, tab, live page, and around.
    var next: Self {
        switch self {
        case .icon: .tab
        case .tab: .live
        case .live: .icon
        }
    }

    /// The verb that turns a card into this shape.
    var showTitle: String {
        switch self {
        case .icon: "Show as Icon"
        case .tab: "Show as Tab"
        case .live: "Show Live Page"
        }
    }

    /// The symbol beside ``showTitle``.
    var symbol: String {
        switch self {
        case .icon: "app"
        case .tab: "rectangle.compress.vertical"
        case .live: "rectangle.expand.vertical"
        }
    }
}

/// One of the eight places a floating card is resized from: its four corners and four edges.
/// The corner or edge opposite the dragged one stays where it is, as with a window.
nonisolated enum FloatingResizeHandle: CaseIterable, Sendable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading

    /// The side of the card that moves horizontally: -1 leading, 1 trailing, 0 neither.
    var horizontal: CGFloat {
        switch self {
        case .topLeading, .leading, .bottomLeading: -1
        case .topTrailing, .trailing, .bottomTrailing: 1
        case .top, .bottom: 0
        }
    }

    /// The side of the card that moves vertically: -1 top, 1 bottom, 0 neither.
    var vertical: CGFloat {
        switch self {
        case .topLeading, .top, .topTrailing: -1
        case .bottomLeading, .bottom, .bottomTrailing: 1
        case .leading, .trailing: 0
        }
    }

    var isCorner: Bool {
        horizontal != 0 && vertical != 0
    }

    /// The size the pointer asks for: `start` grown by `translation` on the handle's sides,
    /// never below zero.
    func proposedSize(from start: CGSize, translation: CGSize) -> CGSize {
        CGSize(
            width: max(0, start.width + translation.width * horizontal),
            height: max(0, start.height + translation.height * vertical),
        )
    }

    /// The card's frame at `size`, with the sides opposite this handle where they were in
    /// `start`. The moving sides stop at `area`'s edges unless `minimum` needs the room; an
    /// axis the handle leaves alone keeps its leading or top side.
    func frame(from start: CGRect, size: CGSize, minimum: CGSize, within area: CGRect) -> CGRect {
        let roomWidth = horizontal < 0 ? start.maxX - area.minX : area.maxX - start.minX
        let roomHeight = vertical < 0 ? start.maxY - area.minY : area.maxY - start.minY
        let width = max(minimum.width, min(size.width, roomWidth))
        let height = max(minimum.height, min(size.height, roomHeight))
        return CGRect(
            x: horizontal < 0 ? start.maxX - width : start.minX,
            y: vertical < 0 ? start.maxY - height : start.minY,
            width: width,
            height: height,
        )
    }

    /// The window-style resize pointer for this handle.
    var pointerPosition: FrameResizePosition {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .trailing: .trailing
        case .bottomTrailing: .bottomTrailing
        case .bottom: .bottom
        case .bottomLeading: .bottomLeading
        case .leading: .leading
        }
    }

    /// The handle's hit zone in a card of `size`, in the card's coordinates: a band `thickness`
    /// wide centered on an edge, or a `corner`-sided square centered on a corner. Edge bands
    /// stop where the corner squares begin.
    func hitFrame(in size: CGSize, thickness: CGFloat, corner: CGFloat) -> CGRect {
        let band = isCorner ? corner : thickness
        func span(_ side: CGFloat, length: CGFloat) -> (origin: CGFloat, extent: CGFloat) {
            switch side {
            case ..<0: (-band / 2, band)
            case 0: (corner / 2, max(0, length - corner))
            default: (length - band / 2, band)
            }
        }
        let x = span(horizontal, length: size.width)
        let y = span(vertical, length: size.height)
        return CGRect(x: x.origin, y: y.origin, width: x.extent, height: y.extent)
    }
}
