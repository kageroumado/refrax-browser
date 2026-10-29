import SwiftUI

/// A compact icon with a rectangular target covering the entire row.
struct ControlIslandRow<Icon: View>: View {
    @ViewBuilder var icon: Icon

    var body: some View {
        icon
            .frame(maxWidth: .infinity)
            .frame(height: ControlIslandPlacement.rowHeight)
            .contentShape(Rectangle())
    }
}
