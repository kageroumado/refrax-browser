import SwiftUI

/// Button providing access to page menu and settings.
///
/// Shows a settings slider icon. Tapping opens the page menu popover
/// with zoom, screenshot, certificate, and other page options.
///
/// Uses a Binding instead of a closure to avoid closure identity issues
/// that cause unnecessary re-renders when the parent view re-evaluates.
struct AddressBarPageMenuButton: View {
    /// Binding to control the page menu visibility.
    @Binding var showsMenu: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            showsMenu = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("addressbar-page-menu")
        .accessibilityLabel("Page settings")
        .help("Page settings")
    }
}
