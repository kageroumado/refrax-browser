import SwiftUI

/// Arrange ▸ Grid, Stacks by Site, Stacks by Group, for the floating layer of the active space.
/// Stacks by Site carries a check while the space keeps its site stacks.
struct FloatingArrangeMenu: View {
    @Environment(TabCanvasManager.self) private var canvas

    var body: some View {
        Menu {
            ForEach(FloatingArrangement.allCases, id: \.self) { arrangement in
                if arrangement == .stacksBySite {
                    Toggle(isOn: Binding(get: { canvas.stacksBySite }, set: { on in
                        if on {
                            canvas.arrange(arrangement)
                        } else {
                            canvas.stopStackingBySite()
                        }
                    })) {
                        Label(arrangement.title, systemImage: arrangement.symbol)
                    }
                } else {
                    Button(arrangement.title, systemImage: arrangement.symbol) { canvas.arrange(arrangement) }
                }
            }
        } label: {
            Label("Arrange", systemImage: "square.grid.3x2")
        }
    }
}

/// Arrange as a button whose choices open in a popover on the side of `arrowEdge`, so a
/// control near the window's bottom opens them upward, inside the window.
struct FloatingArrangeButton: View {
    /// The button's edge the popover opens from: `.top` opens it above the button.
    let arrowEdge: Edge

    @Environment(TabCanvasManager.self) private var canvas
    @State private var isPresented = false

    private enum Layout {
        static let padding: CGFloat = 6
        static let rowHeight: CGFloat = 28
        static let rowPadding: CGFloat = 10
        static let rowCornerRadius: CGFloat = 8
        static let checkWidth: CGFloat = 14
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Arrange", systemImage: "square.grid.3x2")
        }
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(FloatingArrangement.allCases, id: \.self) { arrangement in
                    row(arrangement)
                }
            }
            .padding(Layout.padding)
            .fixedSize()
        }
    }

    private func row(_ arrangement: FloatingArrangement) -> some View {
        let isChecked = arrangement == .stacksBySite && canvas.stacksBySite
        return Button {
            isPresented = false
            if isChecked {
                canvas.stopStackingBySite()
            } else {
                canvas.arrange(arrangement)
            }
        } label: {
            HStack {
                Image(systemName: "checkmark")
                    .opacity(isChecked ? 1 : 0)
                    .frame(width: Layout.checkWidth)
                    .accessibilityHidden(!isChecked)
                Label(arrangement.title, systemImage: arrangement.symbol)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.rowPadding)
            .frame(height: Layout.rowHeight)
            .contentShape(.rect(cornerRadius: Layout.rowCornerRadius))
        }
        .buttonStyle(ArrangeRowStyle(cornerRadius: Layout.rowCornerRadius))
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// A menu-like row: the accent fill under the pointer.
private struct ArrangeRowStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        ArrangeRow(label: configuration.label, cornerRadius: cornerRadius)
    }
}

private struct ArrangeRow: View {
    let label: ButtonStyleConfiguration.Label
    let cornerRadius: CGFloat
    @State private var isHovered = false

    var body: some View {
        label
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? Color.appAccentColor : .clear)
            }
            .onHover { isHovered = $0 }
    }
}
