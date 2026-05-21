import SwiftUI

// MARK: - Sidebar Overlay Content

/// SwiftUI content for the AppKit-animated sidebar overlay.
///
/// This view contains just the sidebar content. The glass effect is applied
/// using NSGlassEffectView in AppKit (see setupSidebarOverlayContainer).
/// Animation is handled by the AppKit container in RefraxWindowController.
///
/// The content respects safe area insets to position below the toolbar.
struct SidebarOverlayContent: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        // Early exit when sidebar is expanded - overlay container is hidden
        if !windowState.isSidebarCollapsed {
            Color.clear
        } else if windowState.effectiveSidebarMode == .compact {
            CompactSidebarContent()
                .frame(width: Refrax.Constants.SidebarAnimation.compactWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Sidebar overlay")
        } else {
            SidebarContentView()
                .frame(width: windowState.sidebarThickness, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Sidebar overlay")
        }
    }
}
