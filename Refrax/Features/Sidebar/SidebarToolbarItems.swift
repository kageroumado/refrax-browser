import SwiftUI

struct SidebarToolbarItems: ToolbarContent {
    let canGoBack: Bool
    let canGoForward: Bool
    @Binding var splitViewVisibility: NavigationSplitViewVisibility
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            SidebarToggleButton(splitViewVisibility: $splitViewVisibility)
        }
        
        ToolbarSpacer()
        
        ToolbarItem(placement: .primaryAction) {
            NavigationButtons(
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                onGoBack: onGoBack,
                onGoForward: onGoForward,
            )
        }
    }
}
