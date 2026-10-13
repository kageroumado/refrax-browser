import SwiftUI

/// The address bar's key while a password save is pending; it opens the save-password prompt.
struct AddressBarSavePasswordButton: View {
    @State private var popoverController: SavePasswordPopoverController?

    var body: some View {
        Button {
            popoverController?.toggle()
        } label: {
            Image(systemName: "key.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.appAccentColor)
        }
        .buttonStyle(.plain)
        .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonWidth)
        .contentShape(Circle())
        .accessibilityIdentifier("addressbar-save-password")
        .accessibilityLabel("Save password")
        .savePasswordPrompt(controller: $popoverController)
    }
}
