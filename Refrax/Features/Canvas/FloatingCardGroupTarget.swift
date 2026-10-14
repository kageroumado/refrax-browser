import SwiftUI

/// The loose card a dragged card would group with: its outline brightens as a group's does
/// under a drop, and a Group capsule says what letting go does. Drawn above every card so the
/// dragged card never covers it.
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
        if let id = canvas.floatingDropCardID, let tab = canvas.visibleFloatingTabs.first(where: { $0.id == id }) {
            let frame = canvas.floatingFrame(for: tab, in: area)
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
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.15), value: id)
            .accessibilityHidden(true)
        }
    }
}
