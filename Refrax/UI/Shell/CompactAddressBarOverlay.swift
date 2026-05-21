import SwiftUI

/// Overlay for displaying the address bar when in compact sidebar mode.
///
/// Positioned with fixed padding from the top-left corner of the window.
/// This avoids the frame reporting issues that occur with popovers.
struct CompactAddressBarOverlay: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        if windowState.showsCompactAddressBar {
            ZStack(alignment: .topLeading) {
                clickCapture

                AddressBar()
                    .glassEffect()
                    .frame(width: Layout.addressBarWidth, height: Layout.addressBarHeight)
                    .padding(.top, Layout.topPadding)
                    .padding(.leading, Layout.leadingPadding)
                    .environment(\.addressBarIsFloating, true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .transition(.move(edge: .top))
        }
    }
    
    private var clickCapture: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.snappy(duration: 0.25)) {
                    windowState.showsCompactAddressBar = false
                }
            }
    }

    private enum Layout {
        static let addressBarWidth: CGFloat = 300
        static let addressBarHeight: CGFloat = 32
        static let topPadding: CGFloat = 10
        static let leadingPadding: CGFloat = 103
    }
}
