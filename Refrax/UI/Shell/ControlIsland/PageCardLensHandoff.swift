import SwiftUI

/// Hands the page card over to the Command Lens that opens in its place.
///
/// The anchored lens unfolds from the card's frame in the window's overlay, so while it is up
/// the card steps back: it fades and settles to a slightly smaller size, so the lens glass that
/// springs from the same frame reads as the card becoming the lens, and it takes no clicks or
/// VoiceOver focus. When the lens closes the card returns. The island animates the handoff
/// snappily; with Reduce Motion the card crossfades at full size.
struct PageCardLensHandoff: ViewModifier {
    let lensIsUp: Bool
    let reduceMotion: Bool

    private enum Layout {
        static let settledScale: CGFloat = 0.96
    }

    func body(content: Content) -> some View {
        content
            .opacity(lensIsUp ? 0 : 1)
            .scaleEffect(lensIsUp && !reduceMotion ? Layout.settledScale : 1, anchor: .leading)
            .allowsHitTesting(!lensIsUp)
            .accessibilityHidden(lensIsUp)
    }
}
