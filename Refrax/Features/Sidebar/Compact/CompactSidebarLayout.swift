import SwiftUI

/// Layout constants shared across all compact sidebar views.
enum CompactSidebarLayout {
    static let buttonSize: CGFloat = 32
    static let buttonSpacing: CGFloat = 8
    static let topControlsPadding: CGFloat = 30
    static let dividerHorizontalPadding: CGFloat = 8
    static let dividerVerticalPadding: CGFloat = 4
    static let popoverPadding: CGFloat = 8
    static let addressBarPopoverWidth: CGFloat = 300
    static let favoritesGridWidth: CGFloat = 280
    static let copiedFeedbackDuration: Duration = .seconds(1)
    static let longHoverDelay: Duration = .milliseconds(200)
    static let addressBarDismissDelay: Duration = .seconds(2)
    static let bottomControlsPadding: CGFloat = 8
    static let favoriteTabIconOffset: CGFloat = -4

    enum Icon {
        static let standardSize: CGFloat = 14
        static let navigationSize: CGFloat = 12
        static let backgroundOpacity: Double = 0.2
    }

    enum Badge {
        static let size: CGFloat = 12
        static let iconSize: CGFloat = 7
        static let backgroundOpacity: Double = 0.9
        static let offset: CGFloat = 2
    }

    enum Group {
        static let separatorHeight: CGFloat = 3
        static let separatorOpacity: Double = 0.6
        static let collapsedBackgroundOpacity: Double = 0.15
        static let childBackgroundOpacity: Double = 0.08
        static let nestedChildBackgroundOpacity: Double = 0.12
        static let iconSize: CGFloat = 16
        static let containerCornerRadius: CGFloat = 12
        static let containerPadding: CGFloat = 2
        static let containerHorizontalPadding: CGFloat = 4
        static let containerBackgroundOpacity: Double = 0.1
    }

    enum Footer {
        static let buttonSize: CGFloat = 24
        static let spacing: CGFloat = 6
    }
}

// MARK: - Button Styles

/// Button style for popover items with hover highlight.
struct CompactPopoverButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: CompactSidebarLayout.Icon.standardSize, weight: .medium))
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> some ShapeStyle {
        if isPressed {
            Color.primary.opacity(0.15)
        } else if isHovering {
            Color.primary.opacity(0.08)
        } else {
            Color.clear
        }
    }
}

/// Button style for space popover menu items with hover highlight.
struct CompactSpacePopoverButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> some ShapeStyle {
        if isPressed {
            Color.primary.opacity(0.15)
        } else if isHovering {
            Color.primary.opacity(0.08)
        } else {
            Color.clear
        }
    }
}
