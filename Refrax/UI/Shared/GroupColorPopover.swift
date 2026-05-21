import SwiftUI

/// A compact popover for selecting tab group colors.
///
/// Provides a grid of predefined colors from the palette.
/// Optimized for popup presentation with immediate application of changes.
struct GroupColorPopover: View {
    @Binding var selectedColor: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: SelectionPopoverLayout.sectionSpacing) {
            header
            colorGrid
        }
        .padding(SelectionPopoverLayout.padding)
        .frame(width: Layout.popoverWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Group Color")
                .font(.headline)

            Spacer()

            previewSwatch
        }
    }

    private var previewSwatch: some View {
        Circle()
            .fill(Color.resolveStoredColor(selectedColor))
            .frame(width: 24, height: 24)
            .overlay(
                Circle()
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1),
            )
    }

    // MARK: - Color Grid

    private var colorGrid: some View {
        LazyVGrid(columns: SelectionPopoverLayout.gridColumns, spacing: SelectionPopoverLayout.gridSpacing) {
            ForEach(GroupColor.allCases, id: \.self) { color in
                colorButton(for: color)
            }
        }
    }

    private func colorButton(for color: GroupColor) -> some View {
        let isSelected = selectedColor == color.rawValue

        return Button {
            selectedColor = color.rawValue
        } label: {
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(
                        width: SelectionPopoverLayout.swatchSize,
                        height: SelectionPopoverLayout.swatchSize,
                    )

                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(
                            width: SelectionPopoverLayout.swatchSize - 4,
                            height: SelectionPopoverLayout.swatchSize - 4,
                        )

                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(
                width: SelectionPopoverLayout.itemSize,
                height: SelectionPopoverLayout.itemSize,
            )
            .background(
                RoundedRectangle(cornerRadius: SelectionPopoverLayout.itemCornerRadius)
                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear),
            )
        }
        .buttonStyle(.plain)
        .help(color.rawValue)
    }
}

// MARK: - Layout Constants

private extension GroupColorPopover {
    enum Layout {
        static let popoverWidth: CGFloat = 200
    }
}
