import SwiftUI

/// One row of the page menu popover, drawn with ``PageMenuRowButtonStyle``.
struct PageMenuItem: View {
    let title: String
    let icon: String
    var iconColor: Color?
    let action: () -> Void

    init(title: String, icon: String, iconColor: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(iconColor ?? .primary)
            }
        }
        .buttonStyle(.pageMenuRow)
    }
}
