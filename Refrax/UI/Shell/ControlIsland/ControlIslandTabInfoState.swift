import Observation

/// Keeps current-tab actions reachable while the pointer or a presented menu uses them.
@Observable
final class ControlIslandTabInfoState {
    private(set) var isHeld = false
    private(set) var isLatched = false
    var isHovered = false
    var isMenuPresented = false

    var isVisible: Bool {
        isHeld || isLatched || isHovered || isMenuPresented
    }

    /// The card's hover-only controls (Copy Address) show while the pointer is on the card or
    /// its options are up; a card that is merely latched or held rests with its three controls.
    var showsHoverExtras: Bool {
        isHovered || isMenuPresented
    }

    func hold() {
        isHeld = true
    }
    func release() {
        isHeld = false
    }
    func show() {
        isLatched = true
    }

    func dismiss() {
        isHeld = false
        isLatched = false
        isHovered = false
        isMenuPresented = false
    }
}
