import SwiftUI

/// Where a dragged row would join the current tab as a pane: the frame the page will have
/// there lights up, with the side it takes.
struct PaneDropZone: View {
    let placement: PanePlacement
    let tab: Tab
    let session: PaneLayoutEditor.Session?
    /// The page's frame in the layer.
    let page: CGRect

    private enum Layout {
        static let inset: CGFloat = 8
        static let symbolSize: CGFloat = 30
    }

    var body: some View {
        if let frame = IslandController.dropFrame(of: placement, joining: tab, editing: session, page: page) {
            let zone = frame.insetBy(dx: Layout.inset, dy: Layout.inset)
            WindowCorner.concentric
                .fill(Color.appAccentColor.opacity(0.14))
                .overlay {
                    WindowCorner.concentric
                        .stroke(Color.appAccentColor.opacity(0.5), lineWidth: 1)
                        .padding(0.5)
                }
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: Layout.symbolSize, weight: .regular))
                        Text(title)
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(Color.appAccentColor)
                }
                .frame(width: max(0, zone.width), height: max(0, zone.height))
                .offset(x: zone.minX, y: zone.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var edge: PaneEdge? {
        if case let .split(split) = placement {
            return split.edge
        }
        return nil
    }

    private var symbol: String {
        edge.map { PaneCommand.openBeside($0).symbol } ?? "plus.rectangle"
    }

    private var title: String {
        switch edge {
        case .leading: "Open on the left"
        case .trailing: "Open on the right"
        case .top: "Open above"
        case .bottom: "Open below"
        case nil: "Open here"
        }
    }
}
