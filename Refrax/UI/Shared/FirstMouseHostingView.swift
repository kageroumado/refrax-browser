import AppKit
import SwiftUI

/// Takes the click that activates a floating page or lens.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}
