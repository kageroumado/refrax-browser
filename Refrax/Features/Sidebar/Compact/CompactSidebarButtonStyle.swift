import SwiftUI

// MARK: - Compact Button Style

/// Button style for compact sidebar buttons with hover effect.
struct CompactSidebarButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .adaptiveBackground(
                configuration.isPressed ? .emphasized : (isHovered ? .subtle : .clear),
                in: SquircleShape(),
            )
            .onHover { isHovered = $0 }
    }
}
