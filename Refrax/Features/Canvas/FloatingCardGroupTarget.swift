import SwiftUI

/// Shows the outline that will join neighboring cards, or the card under a direct group drop.
struct FloatingCardGroupTarget: View {
    let area: CGRect
    @Environment(TabCanvasManager.self) private var canvas

    private enum Layout {
        static let fillOpacity: Double = 0.14
        static let strokeOpacity: Double = 0.9
        static let lineWidth: CGFloat = 2
        static let labelHeight: CGFloat = 28
        static let labelPadding: CGFloat = 10
    }

    var body: some View {
        Group {
            if let id = canvas.floatingDropCardID, let tab = canvas.visibleFloatingTabs.first(where: { $0.id == id }) {
                let frame = canvas.floatingFrame(for: tab, in: area)
                if let bridge = canvas.floatingDropBridge,
                   let movingID = canvas.floatingDropMovingCardID,
                   let moving = canvas.visibleFloatingTabs.first(where: { $0.id == movingID }),
                   let outline = FloatingGroupLayout.outlineFrame(
                       around: [frame, canvas.floatingFrame(for: moving, in: area)], in: area
                   ) {
                    let shape = RoundedRectangle(cornerRadius: FloatingGroupLayout.outlineRadius, style: .continuous)
                    shape.fill(Color.appAccentColor.opacity(Layout.fillOpacity / 2))
                        .frame(width: outline.width, height: outline.height)
                        .offset(x: outline.minX, y: outline.minY)
                    shape.strokeBorder(Color.appAccentColor.opacity(Layout.strokeOpacity), lineWidth: Layout.lineWidth)
                        .frame(width: outline.width, height: outline.height)
                        .offset(x: outline.minX, y: outline.minY)
                    Capsule()
                        .fill(Color.appAccentColor)
                        .frame(width: max(bridge.width, Layout.lineWidth), height: max(bridge.height, Layout.lineWidth))
                        .offset(x: bridge.minX, y: bridge.minY)
                } else {
                    let placement = canvas.floatingPlacement(for: tab)
                    let radius = FloatingCardChrome.cornerRadius(for: placement.shape, isKept: placement.isPinned)
                    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                    ZStack {
                        shape.fill(Color.appAccentColor.opacity(Layout.fillOpacity))
                        shape.strokeBorder(Color.appAccentColor.opacity(Layout.strokeOpacity), lineWidth: Layout.lineWidth)
                        Label("Group", systemImage: "rectangle.3.group")
                            .labelStyle(.titleAndIcon)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, Layout.labelPadding)
                            .frame(height: Layout.labelHeight)
                            .glassEffect(.regular, in: Capsule())
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
