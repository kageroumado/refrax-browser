import SwiftUI

extension View {
    /// The background of a popover whose text is read over pages: a thick material, so the
    /// page under it never shows through the words, over a white page and a black one alike.
    func readablePopoverBackground() -> some View {
        presentationBackground(.thickMaterial)
    }
}
