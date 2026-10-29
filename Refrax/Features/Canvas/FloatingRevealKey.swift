import AppKit

/// A modifier held alone to preview adjacent pages. Combinations remain browser and site shortcuts.
/// Option by default: a Control-click is a secondary click to macOS, and Command is every shortcut.
enum FloatingRevealKey: String, CaseIterable {
    case control
    case option
    case command

    static let `default` = Self.option

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "floatingTabs.revealKey") ?? "") ?? .default
    }

    /// The modifier a control's second meaning answers to (Recent tabs on the islands button):
    /// Option, the macOS convention, unless Option is the reveal key, then Control.
    var secondMeaningFlag: NSEvent.ModifierFlags {
        self == .option ? .control : .option
    }

    var secondMeaningGlyph: String {
        self == .option ? "⌃" : "⌥"
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
