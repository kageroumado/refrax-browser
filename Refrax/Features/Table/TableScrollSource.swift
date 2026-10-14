import AppKit

/// What kind of device a scroll event comes from, which decides how it moves the table.
nonisolated enum TableScrollSource: Equatable, Sendable {
    /// A trackpad or Magic Mouse: phased gestures with momentum.
    case trackpad
    /// A mouse with smooth scrolling: fine deltas with no gesture phases, grouped until
    /// the events stop.
    case smoothWheel
    /// A notched mouse wheel: each event is one step.
    case wheel

    /// Classifies an event by its phases first: only gesture devices send them.
    static func classify(hasPreciseDeltas: Bool, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Self {
        if !phase.isEmpty || !momentumPhase.isEmpty {
            return .trackpad
        }
        return hasPreciseDeltas ? .smoothWheel : .wheel
    }
}
