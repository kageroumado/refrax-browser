import SwiftUI

/// A single menu item button for the page menu popover.
///
/// Provides consistent styling with hover effects and icon alignment
/// matching macOS system menus.
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

    @State private var isHovered = false

    private enum Layout {
        static let cornerRadius: CGFloat = 6
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
        static let iconWidth: CGFloat = 20
        static let spacing: CGFloat = 8
        static let fontSize: CGFloat = 13
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.spacing) {
                Image(systemName: icon)
                    .font(.system(size: Layout.fontSize))
                    .foregroundStyle(iconColor ?? .primary)
                    .frame(width: Layout.iconWidth)

                Text(title)
                    .font(.system(size: Layout.fontSize))

                Spacer()
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(isHovered ? Color.appAccentColor.opacity(0.1) : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
