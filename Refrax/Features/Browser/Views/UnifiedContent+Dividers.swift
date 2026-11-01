import SwiftUI

extension UnifiedContentView {
    /// The lines between panes and the grip that moves them.
    ///
    /// On the page each line fills the one-point gap between its panes; in layout mode each
    /// gap is a bar with a grip in its middle, lit while the pointer is on it. Taking hold is
    /// AppKit (``DividerTrackingView``): a web view sets the cursor on every move, and only a
    /// tracking area's override cursor outlasts it.
    func dividers(grid: PaneGrid, geometry: PaneGridGeometry, isEditing: Bool) -> some View {
        let dividers = geometry.dividers(for: grid)
        let reach = isEditing ? PaneEditingSurface.dividerReach : Layout.dividerReach
        return ZStack(alignment: .topLeading) {
            ForEach(dividers, id: \.axis) { divider in
                if isEditing {
                    LayoutModeDividerBar(divider: divider, isHovered: hoveredRegion == .divider(divider.axis))
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .gridColor))
                        .frame(width: divider.frame.width, height: divider.frame.height)
                        .offset(x: divider.frame.minX, y: divider.frame.minY)
                        .allowsHitTesting(false)
                }
            }
            DividerTrackingView(
                grips: dividers.map { DividerGrip(axis: $0.axis, frame: $0.grabFrame(reach: reach)) },
                onDrag: { axis, location in
                    dragDivider(axis, to: location, geometry: geometry)
                },
                onDragEnded: { axis in
                    finishDividerDrag(axis)
                },
                onHover: { axis in
                    guard isEditing else { return }
                    withAnimation(Layout.hoverAnimation) {
                        hoveredRegion = axis.map(PaneEditingRegion.divider)
                    }
                },
            )
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    private func dragDivider(_ axis: PaneDivider.Axis, to location: CGFloat, geometry: PaneGridGeometry) {
        let ratio = geometry.split(for: axis, at: location)
        if session != nil {
            windowState.editLayout(animated: false) { editor in
                switch axis {
                case .column: editor.setSplits(column: ratio)
                case .row: editor.setSplits(row: ratio)
                }
                return true
            }
        } else {
            dividerDrag = DividerDrag(axis: axis, ratio: ratio)
        }
    }

    /// A released divider rests at a nearby resting point and, on the page, is stored on the tab.
    private func finishDividerDrag(_ axis: PaneDivider.Axis) {
        if let session {
            let ratio = PaneSplitRatio.settled(axis == .column ? session.columnSplit : session.rowSplit)
            windowState.editLayout { editor in
                switch axis {
                case .column: editor.setSplits(column: ratio)
                case .row: editor.setSplits(row: ratio)
                }
                return true
            }
            return
        }
        guard let drag = dividerDrag, drag.axis == axis else { return }
        let configuration = tab.layoutConfiguration
        let ratio = PaneSplitRatio.settled(drag.ratio)
        tab.storePaneSplits(
            column: axis == .column ? ratio : configuration?.horizontalDivider ?? 0.5,
            row: axis == .row ? ratio : configuration?.verticalDivider ?? 0.5,
        )
        dividerDrag = nil
        tabManager.scheduleSave()
    }
}

/// A gap between panes in layout mode, drawn as a bar a resize takes hold of: a faint band the
/// length of the gap and a grip in its middle.
private struct LayoutModeDividerBar: View {
    let divider: PaneDivider
    let isHovered: Bool

    private enum Layout {
        static let gripLength: CGFloat = 44
        static let gripThickness: CGFloat = 5
    }

    var body: some View {
        let frame = divider.frame
        let isColumn = divider.axis == .column
        ZStack {
            RoundedRectangle(cornerRadius: min(frame.width, frame.height) / 2, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.22 : 0.1))
            Capsule()
                .fill(isHovered ? Color.appAccentColor : Color.white.opacity(0.85))
                .frame(
                    width: isColumn ? Layout.gripThickness : min(Layout.gripLength, frame.width),
                    height: isColumn ? min(Layout.gripLength, frame.height) : Layout.gripThickness,
                )
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
