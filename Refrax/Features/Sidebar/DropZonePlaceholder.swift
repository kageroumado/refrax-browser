import SwiftUI

/// Type of drop zone placeholder, determining visual style and labeling.
enum DropZoneType {
    case favorites
    case pinned

    var icon: String {
        switch self {
        case .favorites: "star.fill"
        case .pinned: "pin.fill"
        }
    }

    var text: String {
        switch self {
        case .favorites: "Drop here to favorite"
        case .pinned: "Drop here to pin"
        }
    }

    var accessibilityID: String {
        switch self {
        case .favorites: "DropZone-favorites"
        case .pinned: "DropZone-pinned"
        }
    }

    var height: CGFloat {
        switch self {
        case .favorites: Constants.Layout.tabItemHeight * 1.5
        case .pinned: Constants.Layout.tabItemHeight
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .favorites: 16
        case .pinned: Constants.Layout.tabCornerRadius
        }
    }
}

/// Reusable placeholder view for drag-and-drop zones in the sidebar.
///
/// Displays a dashed border with icon and text to indicate where items can be dropped.
/// Used for both favorites and pin drop zones when those sections are empty.
struct DropZonePlaceholder: View {
    let type: DropZoneType
    let isActive: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: type.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(type.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: type.height)
        .background {
            RoundedRectangle(cornerRadius: type.cornerRadius)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .foregroundStyle(isActive ? Color.secondary : .secondary.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .accessibilityIdentifier(type.accessibilityID)
    }
}
