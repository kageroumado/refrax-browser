import SwiftUI

extension EnvironmentValues {
    /// The rail is resting: its glass is clear and its symbols step back one shade.
    @Entry var controlIslandIsResting = false
}

struct ControlIslandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.controlIslandIsResting) private var isResting

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled && appearsActive && !isResting ? Color.primary : Color.secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
