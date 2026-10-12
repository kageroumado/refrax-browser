import Foundation

nonisolated enum ControlIslandDragTarget: String, CaseIterable {
    case panel, window

    var title: String { self == .panel ? "Control panel" : "Window" }
    var backgroundTarget: Self { self == .panel ? .window : .panel }
    var help: String {
        self == .panel
            ? "Option-drag anywhere on the controls to move the panel. Drag empty glass to move the window."
            : "Option-drag anywhere on the controls to move the window. Drag empty glass to move the panel."
    }
}
