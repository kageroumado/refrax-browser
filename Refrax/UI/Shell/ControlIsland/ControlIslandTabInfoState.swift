import Observation

/// Keeps current-tab actions reachable while the pointer or a presented menu uses them.
@Observable
final class ControlIslandTabInfoState {
    private(set) var isHeld = false
    private(set) var isLatched = false
    /// Unfolded without the pointer asking for it (editing the address, a login to save); it
    /// folds once the pointer has been elsewhere for ``briefShowHold``.
    private(set) var isShownBriefly = false
    var isHovered = false
    var isMenuPresented = false
    /// A prompt the page asked for is open from the card (a login to save). It stays until it
    /// is answered, so the card it points from stays too; only the prompt clears this.
    var isPromptPresented = false

    var isVisible: Bool {
        isHeld || isLatched || isShownBriefly || isHovered || isMenuPresented || isPromptPresented
    }

    /// How long a briefly shown card waits for the pointer before folding back into the rail.
    static let briefShowHold: Duration = .seconds(2.5)

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
    /// Unfolds the card until the pointer has been elsewhere for ``briefShowHold``.
    func showBriefly() {
        isShownBriefly = true
    }
    func foldBriefShow() {
        isShownBriefly = false
    }

    /// Folds the card unless a prompt still points from it.
    func dismiss() {
        isHeld = false
        isLatched = false
        isShownBriefly = false
        isHovered = false
        isMenuPresented = false
    }
}
