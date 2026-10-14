import AppKit

/// A modifier held alone to preview adjacent pages. Combinations remain browser and site shortcuts.
enum FloatingRevealKey: String, CaseIterable {
    case control
    case option
    case command

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "floatingTabs.revealKey") ?? "") ?? .control
    }

    /// Shift extends selection and redirects wheel movement while the arrangement stays visible.
    func matchesHold(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection([.control, .option, .command]) == flag
    }

    var title: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }

    var glyph: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        }
    }

    var cgFlag: CGEventFlags {
        switch self {
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        }
    }
}
