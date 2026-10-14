import SwiftUI

/// The active webpage shares its tab's fixed anchor and the table's camera.
struct TableView: View {
    @Environment(TableController.self) private var table
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas

    private enum Layout {
        static let inspectionCornerRadius: CGFloat = 16
        static let inspectionShadowRadius: CGFloat = 18
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            if let tab = windowState.activeTab {
                let frame = canvas.pageFrame(for: tab, in: table.viewportFrame)
                UnifiedContentView(tab: tab)
                    .frame(width: table.viewport.width, height: table.viewport.height)
                    .clipShape(RoundedRectangle(cornerRadius: canvas.isMomentaryNavigation ? Layout.inspectionCornerRadius : 0, style: .continuous))
                    .background {
                        if canvas.isMomentaryNavigation {
                            RoundedRectangle(cornerRadius: Layout.inspectionCornerRadius, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(color: .black.opacity(0.16), radius: Layout.inspectionShadowRadius, y: 6)
                        }
                    }
                    .overlay {
                        if canvas.isMomentaryNavigation {
                            RoundedRectangle(cornerRadius: Layout.inspectionCornerRadius, style: .continuous)
                                .strokeBorder(.primary.opacity(0.16), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .scaleEffect(canvas.floatingCamera.scale, anchor: .topLeading)
                    .offset(x: frame.minX, y: frame.minY)
                    .task(id: tab.activePage.url) { await table.captureSnapshot(of: tab) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay {
            if canvas.isMomentaryNavigation && !canvas.isActive {
                TableEdgeNavigationView()
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            table.updateViewport(frame)
            focusPage()
        }
        .onChange(of: windowState.activeTabID) { focusPage() }
        .onChange(of: canvas.isMomentaryNavigation) { focusPage() }
        .onChange(of: canvas.isActive) { _, active in
            if !active {
                focusPage()
            }
        }
    }

    private func focusPage() {
        if let tab = windowState.activeTab {
            canvas.focusPage(tab, in: table.viewportFrame)
        }
    }
}

/// A page with nothing to show yet: its favicon (32 pt) and title on the window's tinted
/// background.
struct PagePlaceholder: View {
    let tab: Tab

    @Environment(WindowState.self) private var windowState

    private enum Layout {
        static let spacing: CGFloat = 10
        static let faviconSize: CGFloat = 32
        static let titleWidthFraction: CGFloat = 0.8
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: Layout.spacing) {
                favicon
                Text(tab.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: geometry.size.width * Layout.titleWidthFraction)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(windowState.controlIslandTint)
        .background(.regularMaterial)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var favicon: some View {
        if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: Layout.faviconSize, height: Layout.faviconSize)
        } else {
            Image(systemName: "globe")
                .font(.system(size: Layout.faviconSize * 0.75))
                .foregroundStyle(.secondary)
                .frame(width: Layout.faviconSize, height: Layout.faviconSize)
        }
    }
}
