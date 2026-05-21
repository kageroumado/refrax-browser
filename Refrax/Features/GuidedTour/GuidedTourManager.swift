import SwiftUI

/// Manages the state of the interactive guided tour.
///
/// The tour walks new users through key browser actions step by step.
/// Each step has an instruction and a completion condition detected
/// via `onChange` on observable state properties in `GuidedTourOverlay`.
@Observable
final class GuidedTourManager {
    /// A step in the guided tour.
    enum Step: Int, CaseIterable, Sendable {
        case openCommandLens
        case createFirstTab
        case createSecondTab
        case enterLayoutMode
        case openReferencePane
        case completed
    }

    /// The current tour step, or nil if the tour is not active.
    var currentStep: Step?

    /// Whether the tour is currently running.
    var isActive: Bool { currentStep != nil }

    /// Starts the tour from the beginning.
    func start() {
        currentStep = .openCommandLens
    }

    /// Advances to the next step.
    func advance() {
        guard let current = currentStep,
              let next = Step(rawValue: current.rawValue + 1) else { return }
        currentStep = next
    }

    /// Cancels the tour immediately.
    func cancel() {
        currentStep = nil
    }
}

// MARK: - Step Metadata

extension GuidedTourManager.Step {
    /// The instruction shown to the user for this step.
    var instruction: LocalizedStringKey {
        switch self {
        case .openCommandLens:
            "Press \(Text("⌘T").bold()) to open the Command Lens"
        case .createFirstTab:
            "Type a URL or search term, then press \(Text("Return").bold())"
        case .createSecondTab:
            "Open another tab with \(Text("⌘T").bold())"
        case .enterLayoutMode:
            "Click the split view button in the toolbar"
        case .openReferencePane:
            "Click the reference pane button in the toolbar"
        case .completed:
            "You're all set! Enjoy browsing with Refrax."
        }
    }

    /// SF Symbol icon for this step.
    var icon: String {
        switch self {
        case .openCommandLens: "sparkle.magnifyingglass"
        case .createFirstTab: "globe"
        case .createSecondTab: "plus.square.on.square"
        case .enterLayoutMode: "rectangle.split.2x1"
        case .openReferencePane: "sidebar.right"
        case .completed: "checkmark.circle.fill"
        }
    }

    /// 1-based step number for display.
    var stepNumber: Int { rawValue + 1 }

    /// Total actionable steps (excludes .completed).
    static var totalSteps: Int { Self.allCases.count - 1 }
}
