import SwiftUI

extension UnifiedContentView {
    /// The lines between panes and the grip that moves them.
    ///
    /// On the page each line fills the one-point gap between its panes; in layout mode the
    /// gaps are the lines. The grip is AppKit (``DividerTrackingView``): a web view sets the
    /// cursor on every move, and only a tracking area's override cursor outlasts it.
    func dividers(grid: PaneGrid, geometry: PaneGridGeometry, isEditing: Bool) -> some View {
        let dividers = geometry.dividers(for: grid)
        return ZStack(alignment: .topLeading) {
            if !isEditing {
                ForEach(dividers, id: \.axis) { divider in
                    Rectangle()
                        .fill(Color(nsColor: .gridColor))
                        .frame(width: divider.frame.width, height: divider.frame.height)
                        .offset(x: divider.frame.minX, y: divider.frame.minY)
                        .allowsHitTesting(false)
                }
            }
            DividerTrackingView(
                grips: dividers.map { DividerGrip(axis: $0.axis, frame: $0.grabFrame(reach: Layout.dividerReach)) },
                onDrag: { axis, location in
                    dragDivider(axis, to: location, geometry: geometry)
                },
                onDragEnded: { axis in
                    finishDividerDrag(axis)
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
