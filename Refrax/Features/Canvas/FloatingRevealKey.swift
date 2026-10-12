import AppKit

/// A modifier used alone to recall the arrangement. Combinations remain browser and site shortcuts.
enum FloatingRevealKey: String, CaseIterable {
    case control, option, command

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "floatingTabs.revealKey") ?? "") ?? .control
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
