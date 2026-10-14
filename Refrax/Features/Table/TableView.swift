import AppKit
import SwiftUI

/// The window's pages as slabs on the table, in ``TableScrollView``, with the ribbon that
/// names the row while the table moves.
struct TableView: View {
    @Environment(TableController.self) private var table
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let ribbonInset: CGFloat = 16
        static let ribbonFade: TimeInterval = 0.4
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            TableScrollRepresentable()
            if table.showsRibbon, let text = table.ribbonText {
                TableRibbon(text: text, color: table.ribbonColor)
                    .padding(Layout.ribbonInset)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Layout.ribbonFade), value: table.showsRibbon)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { table.updateViewport($0) }
    }
}

/// Hosts the table's scroll view and gives it the window's environment for the slabs it
/// mounts.
private struct TableScrollRepresentable: NSViewRepresentable {
    @Environment(TableController.self) private var table
    @Environment(\.refraxEnvironment) private var environment

    func makeNSView(context _: Context) -> TableScrollView {
        let view = TableScrollView(frame: .zero)
        let table = table
        let environment = environment
        view.document.tabProvider = { table.tab(for: $0) }
        view.makeSlabView = { tab in
            let host = NSHostingView(rootView: AnyView(TableSlabContent(tab: tab).refraxEnvironment(environment)))
            host.sizingOptions = []
            return host
        }
        view.makeBandView = { row in
            let host = NSHostingView(rootView: AnyView(TableRowBand(row: row).refraxEnvironment(environment)))
            host.sizingOptions = []
            return host
        }
        view.onViewportMoved = { rect, magnification in table.viewportMoved(visibleRect: rect, magnification: magnification) }
        view.onRest = { table.settle() }
        view.onEnter = { table.enter($0) }
        view.onLeaveOverview = { table.leaveOverview() }
        table.scrollView = view
        view.apply(layout: table.layout, geometry: table.geometry)
        return view
    }

    func updateNSView(_: TableScrollView, context _: Context) {}

    static func dismantleNSView(_ view: TableScrollView, coordinator _: ()) {
        view.makeSlabView = nil
        view.makeBandView = nil
    }
}

private extension View {
    @ViewBuilder
    func refraxEnvironment(_ environment: RefraxEnvironment?) -> some View {
        if let environment {
            refraxEnvironment(environment)
        } else {
            self
        }
    }
}

/// One slab: the window's page when current, otherwise the tab's page borrowed the way a
/// docked column borrows it. Its snapshot stays on top until the page paints, and stands in
/// for it in a deep overview.
struct TableSlabContent: View {
    let tab: Tab

    @Environment(TableController.self) private var table
    @Environment(WindowState.self) private var windowState
    @Environment(WebPagePool.self) private var pagePool
    @State private var hasPainted = false

    private enum Layout {
        static let firstPaintProgress = 0.5
        static let firstPaintFade: TimeInterval = 0.15
    }

    private var isCurrent: Bool {
        tab.id == windowState.activeTabID
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TableGeometry.cornerRadius, style: .continuous)
        ZStack {
            if table.showsLivePages {
                livePage
                    .overlay {
                        if isAwaitingFirstPaint {
                            TableSnapshotView(tab: tab)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: Layout.firstPaintFade), value: isAwaitingFirstPaint)
            } else {
                TableSnapshotView(tab: tab)
            }
        }
        .clipShape(shape)
        .task(id: tab.activePage.id) {
            hasPainted = false
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.displayTitle)
    }

    @ViewBuilder
    private var livePage: some View {
        if isCurrent {
            UnifiedContentView(tab: tab)
        } else {
            TableSideLivePage(tab: tab)
        }
    }

    private var isAwaitingFirstPaint: Bool {
        guard hasPainted, let page = pagePool.existingPage(for: tab.activePage) else { return true }
        return page.isLoading && page.estimatedProgress < Layout.firstPaintProgress
    }
}

/// A slab beside the current one, live: it borrows the tab's page and yields it to a docked
/// column or the main page when they ask, showing the snapshot meanwhile.
private struct TableSideLivePage: View {
    let tab: Tab

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
        .onChange(of: pagePool.existingPage(for: tab.activePage)?.ownerWindowID) {
            if livePage?.ownerWindowID != session.id {
                activate()
            }
        }
        .onDisappear { deactivate() }
    }

    private func activate() {
        deactivate()
        guard let page = pagePool.page(for: tab.activePage),
              session.acquire(page, windowID: ObjectIdentifier(windowState)) else { return }
        livePage = page
    }

    private func deactivate() {
        session.release()
        livePage = nil
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

/// A collapsed row: its name, count, and the first favicons on glass; a click opens it.
struct TableRowBand: View {
    let row: TableLayout.Row

    @Environment(TableController.self) private var table
    @Environment(WindowState.self) private var windowState

    private enum Layout {
        static let faviconSize: CGFloat = 18
        static let faviconCount = 8
        static let spacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 18
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TableGeometry.cornerRadius, style: .continuous)
        let color = row.colorString.map(Color.resolveStoredColor) ?? .appAccentColor
        Button {
            table.toggleRowCollapsed(row.id)
        } label: {
            HStack(spacing: Layout.spacing) {
                Capsule().fill(color).frame(width: 4, height: 22)
                Text(row.title.isEmpty ? (windowState.activeSpace?.name ?? "") : row.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(row.slabs.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(row.slabs.prefix(Layout.faviconCount)) { slab in
                        if let tab = table.tab(for: slab.tabID), let data = tab.activePage.faviconData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(width: Layout.faviconSize, height: Layout.faviconSize)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: shape)
        .help("Open \(row.title)")
        .accessibilityLabel("\(row.title), \(row.slabs.count) tabs, collapsed")
    }
}

/// The capsule that names the row under the pointer while the table moves.
private struct TableRibbon: View {
    let text: String
    let color: Color?

    var body: some View {
        HStack(spacing: 8) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
