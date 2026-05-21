import SwiftUI

/// Expandable panel showing shelf items in a grid.
///
/// Appears in the sidebar's bottom bar, expanding upward when triggered.
/// Follows the MediaControlsPanel pattern for consistent styling.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ Shelf                          [↓ All] [🗑] │  ← Header with actions
/// ├─────────────────────────────────────────────┤
/// │ ┌────────┐ ┌────────┐ ┌────────┐            │
/// │ │  📄    │ │  🖼️    │ │  📁    │            │
/// │ │ Text   │ │ img.png│ │doc.pdf │            │
/// │ │  [×]   │ │  [×]   │ │  [×]   │            │
/// │ └────────┘ └────────┘ └────────┘            │
/// └─────────────────────────────────────────────┘
/// ```
struct ShelfPanel: View {
    @Environment(ShelfManager.self) private var shelfManager

    @State private var isHovering = false

    var body: some View {
        Group {
            if shelfManager.isExpanded, shelfManager.hasItems {
                expandedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader

            Divider()
                .padding(.horizontal, 6)

            // Items grid
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: Layout.itemMinWidth), spacing: Layout.itemSpacing),
                    ],
                    spacing: Layout.itemSpacing,
                ) {
                    ForEach(shelfManager.items) { item in
                        ShelfItemView(item: item)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: Layout.maxPanelHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var panelHeader: some View {
        HStack {
            Text("Shelf")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            headerButton(icon: "arrow.down.to.line", help: "Move all to Downloads", identifier: "shelf-move-all") {
                Task {
                    await shelfManager.moveAllToDownloads()
                }
            }

            headerButton(icon: "trash", help: "Clear all items", identifier: "shelf-clear-all") {
                shelfManager.clearAll()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func headerButton(icon: String, help: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(help)
        // Use transaction to limit animation scope and prevent OpacityRendererEffect
        // from creating per-frame updates. The animation is applied only to opacity,
        // not inherited by child views.
        .opacity(isHovering ? 1.0 : 0.0)
        .transaction { transaction in
            transaction.animation = .easeInOut(duration: 0.15)
        }
        .help(help)
    }
}

// MARK: - Layout Constants

private enum Layout {
    /// Maximum height for the panel content area.
    static let maxPanelHeight: CGFloat = 200
    /// Minimum width for grid items.
    static let itemMinWidth: CGFloat = 64
    /// Spacing between grid items.
    static let itemSpacing: CGFloat = 4
}
