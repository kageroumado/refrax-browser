import Foundation

/// One "Drag to move" chip beside the hand, the first time Option is held over the rail.
nonisolated struct ControlIslandOptionDragHint: Equatable {
    /// The `UserDefaults` key that remembers the chip has been shown on this install.
    static let storageKey = "controlIsland.optionDragExplained"

    /// The chip has been shown once on this install.
    var isExplained: Bool

    /// The first `.ready` while unexplained earns the chip and marks it explained.
    mutating func shouldShow(for feedback: ControlIslandDragFeedback) -> Bool {
        guard case .ready = feedback, !isExplained else { return false }
        isExplained = true
        return true
    }
}
