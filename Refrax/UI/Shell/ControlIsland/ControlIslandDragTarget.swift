import Foundation

/// What an Option-drag on the rail moves; dragging the rail's empty glass moves the other.
nonisolated enum ControlIslandDragTarget: String, CaseIterable {
    case panel
    case window

    var title: String {
        self == .panel ? "Controls" : "Window"
    }
    var backgroundTarget: Self {
        self == .panel ? .window : .panel
    }
    var help: String {
        self == .panel
            ? "Option-drag anywhere on the rail moves the controls; dragging empty glass moves the window. The grip under More moves the controls."
            : "Option-drag anywhere on the rail moves the window; dragging empty glass moves the controls. The grip under More moves the controls."
    }
}
