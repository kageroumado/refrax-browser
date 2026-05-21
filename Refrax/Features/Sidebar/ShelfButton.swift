import SwiftUI

/// Trigger button for the shelf panel in the sidebar bottom bar.
///
/// Shows a tray icon with item count when items exist.
/// Only visible when `shelfManager.hasItems` is true.
struct ShelfButton: View {
    @Environment(ShelfManager.self) private var shelfManager

    var body: some View {
        if shelfManager.hasItems {
            Button {
                shelfManager.togglePanel()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(shelfManager.isExpanded ? Color.appAccentColor : .primary)

                    Text("\(shelfManager.items.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(shelfManager.isExpanded ? Color.appAccentColor : .secondary)
                }
                .frame(height: Layout.buttonSize)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Layout.buttonCornerRadius))
            .accessibilityIdentifier("sidebar-shelf")
            .accessibilityLabel("Shelf (\(shelfManager.items.count) items)")
            .help("Shelf")
        }
    }
}

// MARK: - Layout Constants

private enum Layout {
    static let buttonSize: CGFloat = 32
    static let buttonCornerRadius: CGFloat = 16
}
