import SwiftUI

/// A tab's page: its panes on the two-by-two grid, the dividers between them, and, in layout
/// mode, the grid lifted apart for editing.
///
/// Where everything stands comes from plain types: the panes from ``PaneGrid`` (the tab's
/// stored grid, or the edit's in layout mode), their frames from ``PaneGridGeometry``, a
/// drag's landing from ``PaneDrop``, and the edit from ``PaneLayoutEditor`` on the window.
/// The view draws those and forwards gestures to them.
///
/// Each pane's adapter is keyed by its page, so a page keeps its web view while it moves
/// between cells, and the view itself is keyed by its tab (``PageTravelView``).
struct UnifiedContentView: View {
    let tab: Tab

    @Environment(TabManager.self) var tabManager
    @Environment(WindowState.self) var windowState
    @Environment(WebPagePool.self) var pagePool

    @State var size: CGSize = .zero
    /// A divider dragged on the page: the split it sets, shown at once and stored on release.
    @State var dividerDrag: DividerDrag?
    /// A pane dragged in layout mode.
    @State var paneDrag: PaneDragState?

    struct DividerDrag: Equatable {
        let axis: PaneDivider.Axis
        var ratio: Double
    }

    struct PaneDragState: Equatable {
        let pageID: UUID
        var translation: CGSize
        var target: GridCell?
    }

    enum Layout {
        /// Where a pointer takes hold of a divider: this wide across the line.
        static let dividerReach: CGFloat = 9
        static let dragSpring = Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let shadowRadius: CGFloat = 10
        static let shadowOpacity = 0.18
        /// How far a pane moves before it is dragged rather than clicked.
        static let dragThreshold: CGFloat = 6
    }

    // MARK: - Model

    /// The edit of this tab, while the window is in layout mode for it.
    var session: PaneLayoutEditor.Session? {
        guard let session = windowState.paneEditor.session, session.tabID == tab.id else { return nil }
        return session
    }

    /// The panes shown: the edit's grid in layout mode, else the tab's stored one.
    func grid(for session: PaneLayoutEditor.Session?) -> PaneGrid {
        session?.grid ?? tab.paneGrid
    }

    /// Where the panes stand in the page.
    func geometry(for session: PaneLayoutEditor.Session?) -> PaneGridGeometry {
        if let session {
            return session.geometry(in: size)
        }
        let configuration = tab.layoutConfiguration
        var column = configuration?.horizontalDivider ?? 0.5
        var row = configuration?.verticalDivider ?? 0.5
        if let dividerDrag {
            switch dividerDrag.axis {
            case .column: column = dividerDrag.ratio
            case .row: row = dividerDrag.ratio
            }
        }
        return PaneGridGeometry(size: size, columnSplit: column, rowSplit: row, metrics: .page)
    }

    /// Each pane's frame; while a pane is dragged, the others stand where letting go would put
    /// them, and the dragged one where it began.
    func frames(grid: PaneGrid, geometry: PaneGridGeometry) -> [UUID: CGRect] {
        guard size != .zero else { return [:] }
        var frames = geometry.frames(for: grid)
        if let paneDrag, let target = paneDrag.target, let preview = grid.moving(paneDrag.pageID, to: target) {
            for (id, frame) in geometry.frames(for: preview) where id != paneDrag.pageID {
                frames[id] = frame
            }
        }
        return frames
    }

    // MARK: - Body

    var body: some View {
        let session = session
        let grid = grid(for: session)
        let geometry = geometry(for: session)
        let frames = frames(grid: grid, geometry: geometry)
        ZStack(alignment: .topLeading) {
            if let session {
                emptyCells(session: session, geometry: geometry)
            }
            ForEach(tab.pages) { page in
                if let frame = frames[page.id] {
                    pane(page, frame: frame, metrics: geometry.metrics, isEditing: session != nil)
                }
            }
            if grid.count > 1 {
                dividers(grid: grid, geometry: geometry, isEditing: session != nil)
            }
            if session != nil {
                layoutModeControls(grid: grid, geometry: geometry, frames: frames)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .transaction { transaction in
            // A tab's panes move with animation only into, out of, and within layout mode.
            if session == nil, !windowState.isAnimatingLayoutTransition {
                transaction.animation = nil
            }
        }
        .task(id: tab.pages.map(\.id)) {
            // Pages are made here rather than in the body, which only reads them.
            for page in tab.pages where !page.url.isDeepLink {
                pagePool.page(for: page)
            }
        }
    }

    // MARK: - Panes

    private func pane(_ page: TabPage, frame: CGRect, metrics: PaneGridMetrics, isEditing: Bool) -> some View {
        let isDragged = paneDrag?.pageID == page.id
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        return PaneContentWrapper(
            tabPage: page,
            webPage: pagePool.shownPage(for: page),
            frame: frame,
            cornerRadius: metrics.cornerRadius,
            isLayoutMode: isEditing,
            onActivate: { activate(page) },
        )
        .frame(width: frame.width, height: frame.height)
        .background {
            if isEditing {
                shape.fill(.background)
            }
        }
        .overlay {
            if isEditing {
                PaneGlassRim(cornerRadius: metrics.cornerRadius)
            }
        }
        .overlay {
            // Takes the pane's drag in layout mode, where the frozen page ignores the pointer.
            Color.clear
                .contentShape(.rect)
                .allowsHitTesting(isEditing)
                .gesture(paneDragGesture(for: page.id))
        }
        .shadow(color: .black.opacity(isEditing ? Layout.shadowOpacity : 0), radius: isDragged ? Layout.shadowRadius * 2 : Layout.shadowRadius, y: 4)
        .modifier(PaneDragEffect(offset: isDragged ? paneDrag?.translation ?? .zero : .zero))
        .offset(x: frame.minX, y: frame.minY)
        .zIndex(isDragged ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isEditing ? "Pane: \(page.title)" : page.title)
    }

    /// A click in a pane makes it the tab's active pane.
    private func activate(_ page: TabPage) {
        windowState.recordInteraction(with: page.id)
        if tab.pages.count > 1, tab.activePage.id != page.id {
            tabManager.setActivePage(in: tab, page: page)
        }
    }
}

/// The light along a lifted pane's rim.
struct PaneGlassRim: View {
    let cornerRadius: CGFloat

    private static let gradient = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.7), location: 0.0),
            .init(color: .white.opacity(0.3), location: 0.15),
            .init(color: .clear, location: 0.5),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing,
    )

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Self.gradient, lineWidth: 1)
            .blendMode(.plusLighter)
            .compositingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
