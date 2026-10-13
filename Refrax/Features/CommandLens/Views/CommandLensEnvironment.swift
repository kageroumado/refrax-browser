import SwiftUI

/// The anchored lens drawn as the page card it replaces: the card's height, corner radius,
/// leading inset and tint, with the page's favicon where the card shows it, so the card reads
/// as becoming the field rather than being covered by one.
struct CommandLensFieldStyle: Equatable {
    var height: CGFloat
    var cornerRadius: CGFloat
    var leadingInset: CGFloat
    var trailingInset: CGFloat
    var iconSize: CGFloat
    var iconGap: CGFloat
    var tint: Color
}

extension EnvironmentValues {
    @Entry var commandLensIsSmall = false
    @Entry var commandLensFieldStyle: CommandLensFieldStyle?
}
