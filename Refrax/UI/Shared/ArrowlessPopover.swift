import SwiftUI

extension View {
    /// Presents a popover without an arrow.
    ///
    /// This modifier registers the popover with `ArrowlessPopoverSwizzle` so that
    /// only popovers using this modifier appear without arrows. Regular SwiftUI
    /// popovers will display their arrows normally.
    ///
    /// - Parameters:
    ///   - isPresented: Binding controlling popover visibility.
    ///   - arrowEdge: The preferred edge for positioning.
    ///   - content: The popover content view builder.
    func arrowlessPopover(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .trailing,
        @ViewBuilder content: @escaping () -> some View,
    ) -> some View {
        modifier(
            ArrowlessPopoverModifier(
                isPresented: isPresented,
                arrowEdge: arrowEdge,
                content: content,
            ),
        )
    }
}

private struct ArrowlessPopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    @ViewBuilder let content: () -> PopoverContent

    @State private var actuallyPresented = false

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $actuallyPresented, arrowEdge: arrowEdge, content: self.content)
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    // Register before setting local state - this ensures the flag is set
                    // before SwiftUI creates the popover in the next render pass
                    ArrowlessPopoverSwizzle.registerNextPopoverAsArrowless()
                    actuallyPresented = true
                } else {
                    actuallyPresented = false
                }
            }
            .onChange(of: actuallyPresented) { _, newValue in
                // Sync dismissal back to the external binding
                if !newValue, isPresented {
                    isPresented = false
                }
            }
    }
}
