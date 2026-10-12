/// Momentary reveal and the button's persistent reveal share one visibility rule.
nonisolated struct FloatingTabVisibility: Equatable {
    private(set) var isHeld = false
    private(set) var isLatched = false
    private(set) var isManipulating = false

    var isRevealed: Bool {
        isHeld || isLatched || isManipulating
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
        isManipulating = false
    }

    mutating func beginManipulation() {
        isManipulating = true
    }
    mutating func endManipulation() {
        isManipulating = false
    }

    func shows(isPinned: Bool) -> Bool {
        isRevealed || isPinned
    }
}
