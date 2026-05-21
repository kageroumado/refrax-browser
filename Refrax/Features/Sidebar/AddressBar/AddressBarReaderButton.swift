import SwiftUI

/// Button indicating Reader Mode availability in the address bar.
///
/// Shows when Reader Mode is available for the current page.
/// Tapping toggles between Reader and normal view.
struct AddressBarReaderButton: View {
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var foregroundColor: Color {
        if isActive {
            return Color.appAccentColor
        }
        return isHovered ? .primary : .secondary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "doc.richtext.fill" : "doc.richtext")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("addressbar-reader")
        .accessibilityLabel(isActive ? "Exit Reader Mode" : "Enter Reader Mode")
        .help(isActive ? "Exit Reader Mode" : "Enter Reader Mode")
    }
}
