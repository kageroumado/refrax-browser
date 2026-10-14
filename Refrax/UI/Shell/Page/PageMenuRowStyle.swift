import SwiftUI

/// A row of the page menu popover: its icon in a fixed column, its title, and an accent tint
/// while the pointer is on it. A disabled row steps back to secondary; a destructive one reads red.
struct PageMenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PageMenuRow(configuration: configuration)
    }
}

/// Lays a row's icon out in a column as wide as every other row's, so titles align.
struct PageMenuRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: PageMenuRow.Layout.spacing) {
            configuration.icon
                .frame(width: PageMenuRow.Layout.iconWidth)
            configuration.title
            Spacer(minLength: 0)
        }
    }
}

extension ButtonStyle where Self == PageMenuRowButtonStyle {
    static var pageMenuRow: Self {
        .init()
    }
}

extension LabelStyle where Self == PageMenuRowLabelStyle {
    static var pageMenuRow: Self {
        .init()
    }
}

private struct PageMenuRow: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    enum Layout {
        static let cornerRadius: CGFloat = 6
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
        static let iconWidth: CGFloat = 20
        static let spacing: CGFloat = 8
        static let fontSize: CGFloat = 13
    }

    private var foreground: AnyShapeStyle {
        if configuration.role == .destructive {
            AnyShapeStyle(.red)
        } else if isEnabled {
            AnyShapeStyle(.primary)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    var body: some View {
        configuration.label
            .labelStyle(.pageMenuRow)
            .font(.system(size: Layout.fontSize))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(isHovered && isEnabled ? Color.appAccentColor.opacity(0.1) : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { isHovered = $0 }
    }
}
