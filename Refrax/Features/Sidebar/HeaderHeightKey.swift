import SwiftUI

/// Preference key for propagating header height from child to parent view.
///
/// Used to communicate the SidebarHeader's height to SidebarView so it can be
/// passed to TabListView for accurate drag-to-pin calculations.
struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
