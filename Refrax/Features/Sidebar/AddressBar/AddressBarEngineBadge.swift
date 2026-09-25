import SwiftUI

/// The icon of the engine rendering the page, shown before the URL when it isn't system WebKit.
struct AddressBarEngineBadge: View {
    let icon: NSImage
    let engineName: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: Constants.AddressBar.engineBadgeSize, height: Constants.AddressBar.engineBadgeSize)
            .padding(.trailing, 4)
            .accessibilityLabel("Rendered by \(engineName)")
            .help("Rendered by \(engineName)")
    }
}
