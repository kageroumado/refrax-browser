import Observation

/// Keeps current-tab actions reachable while the pointer or a native menu uses them.
@Observable
final class ControlIslandTabInfoState {
    private(set) var isHeld = false
    private(set) var isLatched = false
    var isHovered = false
    var isMenuPresented = false

    var isVisible: Bool { isHeld || isLatched || isHovered || isMenuPresented }

    func hold() { isHeld = true }
    func release() { isHeld = false }
    func show() { isLatched = true }

    func dismiss() {
        isHeld = false
        isLatched = false
        isHovered = false
        isMenuPresented = false
    }
}
