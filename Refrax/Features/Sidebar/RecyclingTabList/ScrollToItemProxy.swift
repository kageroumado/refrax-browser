import Foundation

/// Proxy for programmatic scrolling in the recycling tab list.
///
/// The Coordinator sets itself as the handler, forwarding scroll requests
/// to `NSScrollView.contentView.scroll(to:)`.
@Observable
final class ScrollToItemProxy {
    /// Closure set by the RecyclingTabList Coordinator to handle scroll requests.
    @ObservationIgnored
    var scrollHandler: ((_ itemID: UUID, _ anchor: ScrollAnchor) -> Void)?

    enum ScrollAnchor {
        case top
        case bottom
        case center
    }

    /// Scrolls the tab list to reveal the item with the given ID.
    func scrollTo(_ itemID: UUID, anchor: ScrollAnchor = .center) {
        scrollHandler?(itemID, anchor)
    }
}
