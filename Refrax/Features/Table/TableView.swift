import AppKit
import SwiftUI

/// The window's pages as slabs on a table. Every slab in view, and one beyond it on each
/// side in both axes, is a live page at its slab size, clipped by the window wherever the
/// view rests; motion translates them and never resizes or remounts one.
///
/// Until the table has caught up with a page it has not placed yet, the page fills the view.
struct TableView: View {
    @Environment(TableController.self) private var table
    @Environment(WindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let reducedMotionFade: TimeInterval = 0.15
    }

    var body: some View {
        let camera = table.camera
        let layout = table.layout
        let slabs = camera.bandSlabs(in: layout, at: table.viewpoint)
        let activeTab = windowState.activeTab
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            if let activeTab, layout.position(of: activeTab.id) == nil {
                UnifiedContentView(tab: activeTab)
            } else {
                ForEach(slabs, id: \.tabID) { slab in
                    TableSlabView(tabID: slab.tabID, isCurrent: slab.tabID == activeTab?.id)
                        .frame(width: slab.frame.width, height: slab.frame.height)
                        .offset(x: slab.frame.minX, y: slab.frame.minY)
                        .transition(reduceMotion ? .opacity.animation(.easeOut(duration: Layout.reducedMotionFade)) : .identity)
                }
                TableSeams(slabs: slabs)
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

/// One live slab: the current page, or a side page borrowed the way a floating preview
/// borrows it. Its snapshot (or placeholder) stays on top until the page has painted.
private struct TableSlabView: View {
    let tabID: UUID
    let isCurrent: Bool

    @Environment(TableController.self) private var table
    @Environment(TabManager.self) private var tabManager
    @Environment(WebPagePool.self) private var pagePool
    @State private var hasPainted = false

    private enum Layout {
        /// Load progress at which a waking page has usually drawn its first content.
        static let firstPaintProgress = 0.5
        static let firstPaintFade: TimeInterval = 0.15
    }

    var body: some View {
        if let tab = tabManager.state.tab(for: tabID) {
            livePage(for: tab)
                .overlay {
                    if isAwaitingFirstPaint(tab) {
                        TableSnapshotView(tab: tab)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: Layout.firstPaintFade), value: isAwaitingFirstPaint(tab))
                .task(id: tab.activePage.id) {
                    hasPainted = false
                    // The page is created as the slab mounts; give it a turn to exist.
                    await Task.yield()
                    if let page = pagePool.existingPage(for: tab.activePage) {
                        await page.waitForPresentationUpdate()
                    }
                    guard !Task.isCancelled else { return }
                    hasPainted = true
                }
                .onDisappear {
                    Task { await table.captureSnapshot(of: tab) }
                }
        }
    }

    @ViewBuilder
    private func livePage(for tab: Tab) -> some View {
        if isCurrent {
            UnifiedContentView(tab: tab)
        } else {
            TableSideLivePage(tab: tab)
        }
    }

    /// A slab whose page has not painted since it mounted, or is still waking, keeps its
    /// snapshot on top, so a page never shows blank while it arrives.
    private func isAwaitingFirstPaint(_ tab: Tab) -> Bool {
        guard hasPainted, let page = pagePool.existingPage(for: tab.activePage) else { return true }
        return page.isLoading && page.estimatedProgress < Layout.firstPaintProgress
    }
}

/// A slab beside the current one, live: it borrows the tab's page the way a floating
/// preview does, and shows the snapshot when another surface holds the page.
private struct TableSideLivePage: View {
    let tab: Tab

    @Environment(TableController.self) private var table
    @Environment(WindowState.self) private var windowState
    @Environment(WebPagePool.self) private var pagePool
    @State private var session = FloatingPreviewSession(yields: true)
    @State private var livePage: WebPage?

    var body: some View {
        Group {
            if let livePage, livePage.ownerWindowID == session.id {
                WebViewContainer(page: livePage)
                    .webViewOwnershipID(session.id)
            } else {
                TableSnapshotView(tab: tab)
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

/// A slab's snapshot, top-leading at full resolution, or its favicon and title on the
/// window's tinted background when it has none.
private struct TableSnapshotView: View {
    let tab: Tab

    @Environment(TableController.self) private var table

    var body: some View {
        Group {
            if let image = table.snapshot(for: tab.id) {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                PagePlaceholder(tab: tab)
                    .task(id: tab.id) { table.requestStoredSnapshot(for: tab) }
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(tab.displayTitle)
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
