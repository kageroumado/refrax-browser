import SwiftUI

struct SidebarToggleButton: View {
    @Binding var splitViewVisibility: NavigationSplitViewVisibility
    
    var body: some View {
        Button(action: toggleSidebar) {
            Image(systemName: "sidebar.left")
        }
        .accessibilityIdentifier("sidebar-toggle")
    }
    
    private func toggleSidebar() {
        withAnimation(.easeInOut) {
            if splitViewVisibility == .all {
                splitViewVisibility = .detailOnly
            } else {
                splitViewVisibility = .all
            }
        }
    }
}
