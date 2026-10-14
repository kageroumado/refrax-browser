import AppKit
import SwiftUI

/// The window's pages as slabs on a table: the slabs of the current row fully in view are
/// live, side by side, with snapshots of partly visible ones at the edges; while the view
/// moves, a cover of snapshots slides above them.
///
/// Until the table has caught up with a page it has not placed yet, the page fills the view.
struct TableView: View {
    @Environment(TableController.self) private var table
    @Environment(WindowState.self) private var windowState

    var body: some View {
        let camera = table.camera
        let presented = table.presented
        let slabs = camera.visibleSlabs(in: presented, at: .resting(on: presented))
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            if !table.showsCover, let active = windowState.activeTab, presented.position(of: active.id) == nil {
                UnifiedContentView(tab: active)
            } else {
                ForEach(slabs, id: \.tabID) { slab in
                    TableSlabView(slab: slab, isCurrent: slab.tabID == presented.focusedTabID, viewport: camera.viewport)
                        .frame(width: slab.frame.width, height: slab.frame.height)
                        .offset(x: slab.frame.minX, y: slab.frame.minY)
                }
                TableSeams(slabs: slabs)
            }
            if table.showsCover {
                TableCover()
                    .opacity(table.coverOpacity)
            }
            if let beam = table.beam {
                TableBeam(request: beam, viewport: camera.viewport)
                    .id(beam.revision)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { table.updateViewport($0) }
    }
}

/// One slab at rest: the current page, a live side page, or a snapshot when the slab is
/// partly out of view.
private struct TableSlabView: View {
    let slab: TableVisibleSlab
    let isCurrent: Bool
    let viewport: CGSize

    @Environment(TableController.self) private var table
    @Environment(TabManager.self) private var tabManager
    @Environment(WebPagePool.self) private var pagePool

    private struct DrawKey: Equatable {
        var generation: Int
        var isLive: Bool
        var isCurrent: Bool
        var pageID: UUID?
    }

    var body: some View {
        if let tab = tabManager.state.tab(for: slab.tabID) {
            content(for: tab)
                .task(id: DrawKey(generation: table.restGeneration, isLive: slab.isWhole, isCurrent: isCurrent, pageID: tab.activePage.id)) {
                    let generation = table.restGeneration
                    guard slab.isWhole else { return }
                    if let page = pagePool.existingPage(for: tab.activePage) {
                        await page.waitForPresentationUpdate()
                    }
                    guard !Task.isCancelled else { return }
                    table.slabDidDraw(tab.id, generation: generation)
                }
        }
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        if !slab.isWhole {
            TableSnapshotView(tab: tab, cutEdge: cutEdge)
        } else if isCurrent {
            UnifiedContentView(tab: tab)
        } else {
            TableSideLivePage(tab: tab)
        }
    }

    /// The edge where the viewport cuts the slab.
    private var cutEdge: HorizontalEdge? {
        if slab.frame.minX < -TableCamera.wholeTolerance {
            return .leading
        }
        if slab.frame.maxX > viewport.width + TableCamera.wholeTolerance {
            return .trailing
        }
        return nil
    }
}

/// A slab beside the current one, live: it borrows the tab's page the way a floating
/// preview does, and shows the snapshot when another surface holds the page.
private struct TableSideLivePage: View {
    let tab: Tab

    @Environment(TableController.self) private var table
    @Environment(WindowState.self) private var windowState
    @Environment(WebPagePool.self) private var pagePool
    @State private var session = FloatingPreviewSession()
    @State private var livePage: WebPage?

    var body: some View {
        Group {
            if let livePage, livePage.ownerWindowID == session.id {
                WebViewContainer(page: livePage)
                    .webViewOwnershipID(session.id)
            } else {
                TableSnapshotView(tab: tab, cutEdge: nil)
            }
        }
        .task(id: tab.activePage.id) { activate() }
        .onDisappear { deactivate() }
    }

    private func activate() {
        deactivate()
        guard let page = pagePool.page(for: tab.activePage),
              session.acquire(page, windowID: ObjectIdentifier(windowState)) else { return }
        livePage = page
        table.setSideLive(true, tabID: tab.id)
    }

    private func deactivate() {
        session.release()
        livePage = nil
        table.setSideLive(false, tabID: tab.id)
    }
}

/// A slab drawn from its snapshot, top-leading, dimmed toward `cutEdge` when the viewport
/// cuts it.
private struct TableSnapshotView: View {
    let tab: Tab
    let cutEdge: HorizontalEdge?

    @Environment(TableController.self) private var table

    private enum Layout {
        static let cutDimming: Double = 0.22
        static let placeholderSpacing: CGFloat = 8
        static let faviconSize: CGFloat = 20
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let image = table.snapshot(for: tab.id) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                placeholder
                    .task(id: tab.id) { table.requestSnapshot(for: tab) }
            }
            if let cutEdge {
                LinearGradient(
                    colors: [Color.black.opacity(Layout.cutDimming), .clear],
                    startPoint: cutEdge == .leading ? .leading : .trailing,
                    endPoint: cutEdge == .leading ? .trailing : .leading,
                )
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(tab.displayTitle)
    }

    private var placeholder: some View {
        VStack(spacing: Layout.placeholderSpacing) {
            if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: Layout.faviconSize, height: Layout.faviconSize)
            } else {
                Image(systemName: "globe").font(.title3).foregroundStyle(.secondary)
            }
            Text(tab.displayTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding()
    }
}

/// Hairlines between slabs that abut in view.
private struct TableSeams: View {
    let slabs: [TableVisibleSlab]

    var body: some View {
        let seams = seams
        ForEach(seams.indices, id: \.self) { index in
            let seam = seams[index]
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: seam.width, height: seam.height)
                .offset(x: seam.minX, y: seam.minY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A 1-pt line on each boundary between neighbors in the same row, on whole points.
    private var seams: [CGRect] {
        zip(slabs, slabs.dropFirst()).compactMap { left, right in
            guard left.position.row == right.position.row, right.position.slab == left.position.slab + 1 else { return nil }
            return CGRect(x: left.frame.maxX.rounded() - 0.5, y: left.frame.minY, width: 1, height: left.frame.height)
        }
    }
}

/// Every visible slab drawn from its snapshot at the moving viewpoint, over the rest layer.
private struct TableCover: View {
    @Environment(TableController.self) private var table
    @Environment(TabManager.self) private var tabManager

    var body: some View {
        let camera = table.camera
        let slabs = camera.visibleSlabs(in: table.layout, at: table.viewpoint)
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            ForEach(slabs, id: \.tabID) { slab in
                if let tab = tabManager.state.tab(for: slab.tabID) {
                    TableSnapshotView(tab: tab, cutEdge: nil)
                        .frame(width: slab.frame.width, height: slab.frame.height)
                        .offset(x: slab.frame.minX, y: slab.frame.minY)
                }
            }
            TableSeams(slabs: slabs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

/// The guide beam from the slab focus left to the one it reached.
private struct TableBeam: View {
    let request: BrowserBeamCues.Request
    let viewport: CGSize

    @Environment(TableController.self) private var table

    var body: some View {
        let bounds = CGRect(origin: .zero, size: viewport)
        LightTravel(
            paths: [request.style.path(request.points(in: bounds), color: LightStyle.color)],
            timing: request.style.timing,
        ) {
            table.finishBeam(request)
        }
        .frame(width: viewport.width, height: viewport.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
