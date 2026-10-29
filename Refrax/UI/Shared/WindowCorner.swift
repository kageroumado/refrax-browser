import SwiftUI

/// The corner every window has on this macOS, and the shape of the glass that floats over a
/// page: concentric with the window's corner where it sits near one, and the window's own
/// radius where it floats free.
nonisolated enum WindowCorner {
    /// The radius of a window's corner, titled or panel alike.
    static let radius: CGFloat = 16

    /// The shape for glass over the page. Resolves against the window's content as the
    /// container shape, which the layers over the page declare with ``View/windowContainerShape()``.
    static var concentric: ConcentricRectangle {
        .rect(corners: .concentric(minimum: .fixed(radius)))
    }
}

extension View {
    /// Declares the view, which fills a window's content, as the container that concentric
    /// shapes over the page resolve against.
    func windowContainerShape() -> some View {
        containerShape(.rect(cornerRadius: WindowCorner.radius))
    }
}
