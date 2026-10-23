/// Momentary reveal and the button's persistent reveal share one visibility rule.
nonisolated struct FloatingTabVisibility: Equatable {
    private(set) var isHeld = false
    private(set) var isLatched = false

    var isRevealed: Bool {
        isHeld || isLatched
    }

    mutating func hold() {
        isHeld = true
    }
    mutating func release() {
        isHeld = false
    }
    mutating func toggle() {
        isLatched.toggle()
    }
    mutating func dismiss() {
        isHeld = false
        isLatched = false
    }
}
