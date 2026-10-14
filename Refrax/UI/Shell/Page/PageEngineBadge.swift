import SwiftUI

/// The icon of the engine rendering the page, shown before the URL when it isn't system WebKit.
struct PageEngineBadge: View {
    let icon: NSImage
    let engineName: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: Constants.PageControls.engineBadgeSize, height: Constants.PageControls.engineBadgeSize)
            .padding(.trailing, 4)
            .accessibilityLabel("Rendered by \(engineName)")
            .help("Rendered by \(engineName)")
    }
}
