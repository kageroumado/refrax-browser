import Foundation

/// What an island looks like: its group's name, icon, and color, edited together.
nonisolated struct IslandAppearance: Equatable, Sendable {
    var name: String
    /// An SF Symbol name or a single emoji; `nil` shows no icon.
    var iconName: String?
    /// A ``GroupColor`` raw value or a tagged P3 string.
    var colorString: String

    /// This appearance with `edit` taken in: the name trimmed, a blank name keeping the one
    /// there, a blank icon clearing it.
    func applying(_ edit: Self) -> Self {
        let name = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = edit.iconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(
            name: name.isEmpty ? self.name : name,
            iconName: icon?.isEmpty == false ? icon : nil,
            colorString: edit.colorString.isEmpty ? colorString : edit.colorString,
        )
    }

    /// Whether `icon` is an emoji, drawn as text, rather than an SF Symbol name.
    static func isEmoji(_ icon: String) -> Bool {
        guard icon.count == 1, let scalar = icon.unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || icon.unicodeScalars.count > 1)
    }
}
