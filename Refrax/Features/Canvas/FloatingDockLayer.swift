import AppKit
import SwiftUI

/// Pages docked to the window's sides, each live at its column's full size, the seams that
/// resize them, and the silhouette of the column a dragged card would take.
struct FloatingDockLayer: View {
    let area: CGRect

    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let silhouetteFade: TimeInterval = 0.15
        static let silhouetteGrowth: CGFloat = 0.96
    }

    var body: some View {
        let columns = canvas.dockColumns(in: area)
        ZStack(alignment: .topLeading) {
            if let target = canvas.dockTarget, let frame = canvas.dockColumns(in: area, previewing: target)[target.edge] {
                FloatingDockSilhouette()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(
                        scale: Layout.silhouetteGrowth, anchor: target.edge == .leading ? .leading : .trailing,
                    )))
            }
            ForEach(FloatingDockEdge.allCases, id: \.self) { edge in
                if let tab = canvas.dockedTab(on: edge), let frame = columns[edge] {
                    FloatingDockColumn(tab: tab, edge: edge, frame: frame, area: area)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .id(tab.id)
                        .transition(.opacity)
                    FloatingDockSeam(edge: edge, column: frame, area: area)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: Layout.silhouetteFade), value: canvas.dockTarget)
        .onChange(of: windowState.activeTabID, initial: true) { canvas.releaseDockForCurrentPage() }
    }
}

/// The macOS tiling preview: a translucent, accent-tinted glass column.
private struct FloatingDockSilhouette: View {
    private enum Layout {
        static let tintOpacity: Double = 0.16
        static let strokeOpacity: Double = 0.35
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FloatingDockLayout.cornerRadius, style: .continuous)
        shape.fill(Color.appAccentColor.opacity(Layout.tintOpacity))
            .glassEffect(.clear.tint(Color.appAccentColor.opacity(Layout.tintOpacity)), in: shape)
            .overlay { shape.strokeBorder(Color.appAccentColor.opacity(Layout.strokeOpacity), lineWidth: 1) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A docked page: a slim header over the live page, on glass concentric with the window.
private struct FloatingDockColumn: View {
    let tab: Tab
    let edge: FloatingDockEdge
    let frame: CGRect
    let area: CGRect

    @Environment(TabCanvasManager.self) private var canvas
    @State private var isHovered = false
    @State private var dragOffset: CGSize = .zero

    private enum Layout {
        static let headerControlSize: CGFloat = 32
        static let headerControlSpacing: CGFloat = 2
        static let headerInset: CGFloat = 10
        /// How much of a header drag the column follows before it lets go of its side.
        static let dragResistance: CGFloat = 0.35
    }

    private var pageSize: CGSize {
        CGSize(
            width: max(1, frame.width - FloatingTabPlacement.previewInset * 2),
            height: max(1, frame.height - FloatingTabPlacement.headerHeight - FloatingTabPlacement.previewInset),
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: FloatingTabPlacement.headerHeight)
            FloatingTabPreview(tab: tab, viewportSize: pageSize)
                .frame(width: pageSize.width, height: pageSize.height)
                .clipShape(.rect(cornerRadius: FloatingDockLayout.cornerRadius - FloatingTabPlacement.previewInset, style: .continuous))
                .padding([.horizontal, .bottom], FloatingTabPlacement.previewInset)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: FloatingDockLayout.cornerRadius, style: .continuous))
        .offset(dragOffset)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Docked page, \(tab.displayTitle)")
        .accessibilityAction(named: "Undock") { canvas.undock(tab) }
        .accessibilityAction(named: "Close Tab") { canvas.closeFloatingTab(tab) }
        .closesOnMiddleClick(tab)
    }

    private var header: some View {
        HStack(spacing: Layout.headerControlSpacing) {
            HStack(spacing: 7) {
                if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "globe").frame(width: 16, height: 16)
                }
                FloatingTabTitle(tab: tab)
                TabStateSymbols(tab: tab)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { canvas.openFloatingTab(tab) }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("floatingTabs"))
                .onChanged { value in
                    dragOffset = CGSize(
                        width: value.translation.width * Layout.dragResistance,
                        height: value.translation.height * Layout.dragResistance,
                    )
                }
                .onEnded { value in
                    if FloatingDockLayout.undocks(after: value.translation, from: edge) {
                        dragOffset = .zero
                        canvas.undock(tab)
                    } else {
                        withAnimation(TabCanvasManager.dockAnimation) { dragOffset = .zero }
                    }
                })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { canvas.openFloatingTab(tab) }

            headerButton("Undock", symbol: "arrow.uturn.backward") { canvas.undock(tab) }
            headerButton("Close Tab", symbol: "xmark") { canvas.closeFloatingTab(tab) }
            PageActionsMenu(tab: tab, surface: .floatingCard, area: area)
                .frame(width: Layout.headerControlSize, height: Layout.headerControlSize)
                .opacity(isHovered || canvas.menuTabID == tab.id ? 1 : 0)
                .allowsHitTesting(isHovered || canvas.menuTabID == tab.id)
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .buttonStyle(.plain)
        .padding(.horizontal, Layout.headerInset)
    }

    /// A header control that shows on hover and stays reachable by accessibility.
    private func headerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .foregroundStyle(.secondary)
            .frame(width: Layout.headerControlSize, height: Layout.headerControlSize)
            .contentShape(Rectangle())
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .help(title)
            .accessibilityLabel(title)
    }
}

/// The divider between a docked column and the page: dragging it sets the column's width.
private struct FloatingDockSeam: View {
    let edge: FloatingDockEdge
    let column: CGRect
    let area: CGRect

    @Environment(TabCanvasManager.self) private var canvas

    private enum Layout {
        /// How far one accessibility adjustment moves the seam.
        static let adjustmentStep: CGFloat = 40
    }

    var body: some View {
        let frame = FloatingDockLayout.seamFrame(beside: column, edge: edge)
        Color.clear
            .contentShape(Rectangle())
            .frame(width: frame.width, height: frame.height)
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("floatingTabs"))
                .onChanged { value in canvas.resizeDock(on: edge, seamAt: value.location.x, in: area) })
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityElement()
            .accessibilityLabel("Docked page width")
            .accessibilityAdjustableAction { direction in
                let wider = direction == .increment
                let step = (edge == .leading) == wider ? Layout.adjustmentStep : -Layout.adjustmentStep
                canvas.resizeDock(on: edge, seamAt: frame.midX + step, in: area)
            }
    }
}
