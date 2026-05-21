import SwiftUI

/// Shared layout constants for selection grid popovers.
///
/// Used by `GroupColorPopover`, `GroupIconPopover`, and `SpaceIconPopover` to maintain
/// consistent spacing and sizing across all grid-based selection UIs.
enum SelectionPopoverLayout {
    static let padding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let gridSpacing: CGFloat = 6
    static let itemSize: CGFloat = 32
    static let itemCornerRadius: CGFloat = 6
    static let previewSize: CGFloat = 36
    static let previewCornerRadius: CGFloat = 8
    static let swatchSize: CGFloat = 24
    static let emojiFontSize: CGFloat = 16
    static let symbolFontSize: CGFloat = 14

    /// Creates adaptive grid columns for selection items.
    static var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: itemSize), spacing: gridSpacing)]
    }
}

/// A reusable selection item button with highlight and selection styling.
///
/// Wraps content in a button with standard selection appearance matching
/// the design used in GroupIconPopover and SpaceIconPopover.
struct SelectionItemButton<Content: View>: View {
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .frame(
                    width: SelectionPopoverLayout.itemSize,
                    height: SelectionPopoverLayout.itemSize,
                )
                .background(
                    RoundedRectangle(cornerRadius: SelectionPopoverLayout.itemCornerRadius)
                        .fill(isSelected ? accentColor.opacity(0.2) : Color.clear),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SelectionPopoverLayout.itemCornerRadius)
                        .strokeBorder(
                            isSelected ? accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 1.5,
                        ),
                )
        }
        .buttonStyle(.plain)
    }
}

/// A preview icon container with standard styling.
///
/// Shows a preview of the selected item with a rounded background
/// in the popover header.
struct SelectionPreviewContainer<Content: View>: View {
    let accentColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SelectionPopoverLayout.previewCornerRadius)
                .fill(accentColor.opacity(0.15))
                .frame(
                    width: SelectionPopoverLayout.previewSize,
                    height: SelectionPopoverLayout.previewSize,
                )

            content
        }
    }
}
