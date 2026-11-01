import SwiftUI

// MARK: - Layout mode

extension UnifiedContentView {
    /// The surface layout mode edits on: the page dimmed behind the panes.
    var layoutModeBackdrop: some View {
        Rectangle()
            .fill(Color(nsColor: .underPageBackgroundColor))
            .overlay(Color.black.opacity(0.45))
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// Takes the pointer everywhere on the surface the controls leave free: hovering marks the
    /// pane or bar under it, and a drag that starts on a pane moves the pane.
    func layoutModeSurface(grid: PaneGrid, geometry: PaneGridGeometry) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(.rect)
            .onContinuousHover(coordinateSpace: .named(Layout.surfaceSpace)) { trackHover($0, grid: grid, geometry: geometry) }
            .pointerStyle(surfacePointer)
            .gesture(paneDragGesture(grid: grid, geometry: geometry))
            .accessibilityHidden(true)
    }

    /// Marks the pane or bar under the pointer.
    func trackHover(_ phase: HoverPhase, grid: PaneGrid, geometry: PaneGridGeometry) {
        switch phase {
        case let .active(point):
            let region = PaneEditingSurface.region(at: point, in: grid, geometry: geometry)
            if hoveredRegion != region {
                withAnimation(Layout.hoverAnimation) { hoveredRegion = region }
            }
        case .ended:
            // Over a divider's grip the AppKit grip view has the pointer and reports it.
            if case .divider = hoveredRegion {
                return
            }
            withAnimation(Layout.hoverAnimation) { hoveredRegion = nil }
        }
    }

    /// A hand over a pane, closed while one is dragged.
    private var surfacePointer: PointerStyle? {
        if paneDrag != nil {
            return .grabActive
        }
        if case .pane = hoveredRegion {
            return .grabIdle
        }
        return nil
    }

    /// The empty cells of the edit: each opens a page there, takes a dropped row, and offers
    /// the panes beside it a way to grow over it.
    func emptyCells(session: PaneLayoutEditor.Session, geometry: PaneGridGeometry) -> some View {
        ForEach(session.grid.emptyCells, id: \.self) { cell in
            let frame = geometry.frame(of: cell)
            EmptyPaneCell(
                cell: cell,
                cornerRadius: geometry.metrics.cornerRadius,
                growers: growers(into: cell, grid: session.grid),
                onOpen: {
                    windowState.newPanePlacement = .cell(cell)
                    windowState.openCommandLens()
                },
                onGrow: { pageID, edge in
                    windowState.editLayout { $0.expand(pageID, toward: edge) }
                },
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .transition(.opacity)
        }
    }

    /// The panes beside `cell` that can grow over it, by the side of the cell they are on.
    private func growers(into cell: GridCell, grid: PaneGrid) -> [PaneEdge: UUID] {
        var growers: [PaneEdge: UUID] = [:]
        for edge in PaneEdge.allCases {
            guard let neighbor = cell.neighbor(across: edge), let pageID = grid.page(at: neighbor),
                  grid.expanding(pageID, toward: edge.opposite) != nil else { continue }
            growers[edge] = pageID
        }
        return growers
    }

    /// Each pane's controls, where a dragged pane would land, and the bar that ends the mode.
    func layoutModeControls(grid: PaneGrid, geometry: PaneGridGeometry, frames: [UUID: CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            if let paneDrag {
                PaneLandingFrame(move: paneDrag.move, pageID: paneDrag.pageID, grid: grid, geometry: geometry)
            }
            ForEach(tab.pages) { page in
                if let frame = frames[page.id] {
                    // A card is a handle too: a drag that starts on it, off its buttons, moves the
                    // pane. It stays in place, hidden, while its drag runs, so the drag lives on.
                    PaneEditingControls(
                        page: page,
                        verbs: PaneEditingVerbs(pageID: page.id, grid: grid),
                        style: PaneEditingSurface.controlStyle(for: frame.size),
                        onVerb: { perform($0, on: page) },
                    )
                    .onContinuousHover(coordinateSpace: .named(Layout.surfaceSpace)) { trackHover($0, grid: grid, geometry: geometry) }
                    .pointerStyle(paneDrag != nil ? .grabActive : .grabIdle)
                    .gesture(paneDragGesture(grid: grid, geometry: geometry))
                    .opacity(paneDrag == nil ? 1 : 0)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(.opacity)
                }
            }
            LayoutModeBar(title: tab.displayTitle) { windowState.exitLayoutMode() }
                .frame(width: size.width, height: LayoutModeBarMetrics.height)
                .offset(y: size.height - LayoutModeBarMetrics.spacing - LayoutModeBarMetrics.height)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func perform(_ verb: PaneEditingVerbs.Verb, on page: TabPage) {
        switch verb {
        case let .grow(edge):
            windowState.editLayout { $0.expand(page.id, toward: edge) }
        case let .shrink(edge):
            windowState.editLayout { $0.shrink(page.id, from: edge) }
        case .openAsTab:
            tabManager.movePageToNewTab(page, from: tab)
        case .close:
            tabManager.removePageFromTab(tab, page: page)
        }
    }

    /// A pane moved in layout mode: a drag that starts on a pane (or its card) carries it, the
    /// pane where it would land steps aside, and letting go trades their places.
    func paneDragGesture(grid: PaneGrid, geometry: PaneGridGeometry) -> some Gesture {
        DragGesture(minimumDistance: Layout.dragThreshold, coordinateSpace: .named(Layout.surfaceSpace))
            .onChanged { value in
                let pageID: UUID
                if let dragged = paneDrag?.pageID {
                    pageID = dragged
                } else if case let .pane(id) = PaneEditingSurface.region(at: value.startLocation, in: grid, geometry: geometry) {
                    pageID = id
                } else {
                    return
                }
                let move = PaneDrop.move(pageID, by: value.translation, in: grid, geometry: geometry)
                if paneDrag?.move != move || paneDrag == nil {
                    withAnimation(Layout.dragSpring) {
                        paneDrag = PaneDragState(pageID: pageID, translation: value.translation, move: move)
                    }
                } else {
                    paneDrag?.translation = value.translation
                }
            }
            .onEnded { _ in
                if let paneDrag, case let .lands(cell, _) = paneDrag.move {
                    windowState.editLayout { $0.move(paneDrag.pageID, to: cell) }
                }
                withAnimation(Layout.dragSpring) {
                    paneDrag = nil
                }
            }
    }
}

// MARK: - Views

/// A pane's controls in layout mode, centered on the pane: its icon with an arrow toward each
/// side it can grow or give up, its title and site, and the verbs that take it out of the split.
struct PaneEditingControls: View {
    let page: TabPage
    let verbs: PaneEditingVerbs
    let style: PaneEditingSurface.ControlStyle
    let onVerb: (PaneEditingVerbs.Verb) -> Void

    private enum Layout {
        static let faviconSize: CGFloat = 32
        static let compactFaviconSize: CGFloat = 20
        static let arrowSize: CGFloat = 36
        static let compactArrowSize: CGFloat = 28
        static let padSpacing: CGFloat = 6
        static let titleWidth: CGFloat = 240
        static let padding: CGFloat = 18
        static let cornerRadius: CGFloat = 22
    }

    var body: some View {
        Group {
            switch style {
            case .full: full
            case .compact: compact
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pane: \(page.title)")
    }

    private var full: some View {
        VStack(spacing: 12) {
            pad(favicon: Layout.faviconSize, arrow: Layout.arrowSize)
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(page.url.safeDisplayDomain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: Layout.titleWidth)
            HStack(spacing: 8) {
                Button(PaneEditingVerbs.title(of: .openAsTab), systemImage: PaneEditingVerbs.symbol(of: .openAsTab)) { onVerb(.openAsTab) }
                Button(PaneEditingVerbs.title(of: .close), systemImage: PaneEditingVerbs.symbol(of: .close), role: .destructive) { onVerb(.close) }
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .disabled(!verbs.canLeave)
        }
        .padding(Layout.padding)
    }

    private var compact: some View {
        HStack(spacing: 8) {
            pad(favicon: Layout.compactFaviconSize, arrow: Layout.compactArrowSize)
            Menu {
                Button(PaneEditingVerbs.title(of: .openAsTab), systemImage: PaneEditingVerbs.symbol(of: .openAsTab)) { onVerb(.openAsTab) }
                Button(PaneEditingVerbs.title(of: .close), systemImage: PaneEditingVerbs.symbol(of: .close), role: .destructive) { onVerb(.close) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: Layout.compactArrowSize, height: Layout.compactArrowSize)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!verbs.canLeave)
            .help("More for \(title)")
        }
        .padding(10)
    }

    private var title: String {
        page.title.isEmpty ? page.url.safeDisplayDomain : page.title
    }

    /// The page's icon with an arrow on each side it can act toward: three by three, the
    /// corners empty; the icon alone when no side can change.
    @ViewBuilder
    private func pad(favicon: CGFloat, arrow: CGFloat) -> some View {
        if verbs.sides.isEmpty {
            FaviconView(data: page.faviconData, url: page.url, size: favicon)
        } else {
            sidePad(favicon: favicon, arrow: arrow)
        }
    }

    private func sidePad(favicon: CGFloat, arrow: CGFloat) -> some View {
        Grid(horizontalSpacing: Layout.padSpacing, verticalSpacing: Layout.padSpacing) {
            GridRow {
                Color.clear.frame(width: arrow, height: arrow)
                side(.top, size: arrow)
                Color.clear.frame(width: arrow, height: arrow)
            }
            GridRow {
                side(.leading, size: arrow)
                FaviconView(data: page.faviconData, url: page.url, size: favicon)
                    .frame(width: arrow, height: arrow)
                side(.trailing, size: arrow)
            }
            GridRow {
                Color.clear.frame(width: arrow, height: arrow)
                side(.bottom, size: arrow)
                Color.clear.frame(width: arrow, height: arrow)
            }
        }
    }

    @ViewBuilder
    private func side(_ edge: PaneEdge, size: CGFloat) -> some View {
        if let verb = verbs.sides[edge] {
            let grows = if case .grow = verb {
                true
            } else {
                false
            }
            Button {
                onVerb(verb)
            } label: {
                Image(systemName: PaneEditingVerbs.symbol(of: verb))
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(grows ? Color.white : Color.primary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(grows ? Color.appAccentColor : Color.primary.opacity(0.1)))
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(PaneEditingVerbs.title(of: verb))
            .accessibilityLabel(PaneEditingVerbs.title(of: verb))
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// Where a dragged pane would land: the frame it takes, outlined in the accent color, or, over
/// a cell it cannot take, that cell outlined in red with why.
struct PaneLandingFrame: View {
    let move: PaneMove
    let pageID: UUID
    let grid: PaneGrid
    let geometry: PaneGridGeometry

    var body: some View {
        switch move {
        case .stays:
            EmptyView()
        case let .lands(_, landed):
            if let span = landed.span(of: pageID) {
                outline(geometry.frame(of: span), color: Color.appAccentColor, message: nil)
            }
        case let .refused(cell):
            let span = grid.page(at: cell).flatMap(grid.span(of:)) ?? PaneSpan(cell)
            outline(geometry.frame(of: span), color: .red, message: "This pane can’t go here")
        }
    }

    private func outline(_ frame: CGRect, color: Color, message: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: geometry.metrics.cornerRadius, style: .continuous)
        return shape
            .strokeBorder(color, lineWidth: 3)
            .background(shape.fill(color.opacity(0.12)))
            .overlay {
                if let message {
                    Label(message, systemImage: "nosign")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityLabel(message ?? "Drop here")
    }
}

/// A cell no pane covers in layout mode: a dashed target where a page opens from the Command
/// Lens or a row from an island lands, with an arrow from each pane beside it that can grow
/// over it.
struct EmptyPaneCell: View {
    let cell: GridCell
    let cornerRadius: CGFloat
    /// The pane on each side of the cell that can grow over it.
    let growers: [PaneEdge: UUID]
    let onOpen: () -> Void
    let onGrow: (UUID, PaneEdge) -> Void

    private enum Layout {
        static let symbolSize: CGFloat = 30
        static let arrowInset: CGFloat = 14
        static let arrow: CGFloat = 34
        static let dash: [CGFloat] = [10, 7]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(0.06))
            shape.strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: Layout.dash))
            Button(action: onOpen) {
                VStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: Layout.symbolSize, weight: .light))
                    Text("Open a page here")
                        .font(.headline)
                    Text("or drop a tab from an island")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open a page in the \(cell) cell")
            ForEach(growers.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { edge in
                if let pageID = growers[edge] {
                    Button {
                        onGrow(pageID, edge.opposite)
                    } label: {
                        Image(systemName: PaneEditingVerbs.arrow(toward: edge.opposite))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Layout.arrow, height: Layout.arrow)
                            .background(Circle().fill(Color.appAccentColor))
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .help("Grow the pane beside it over this cell")
                    .accessibilityLabel("Grow the pane on the \(edge.rawValue) over this cell")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: edge))
                    .padding(Layout.arrowInset)
                }
            }
        }
    }

    private func alignment(for edge: PaneEdge) -> Alignment {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }
}

/// The bar in the editing surface's bottom margin: what is being edited, how, and Done
/// (Return or Esc).
struct LayoutModeBar: View {
    let title: String
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Label("Editing Split View", systemImage: "rectangle.split.2x2")
                .font(.system(size: 13, weight: .semibold))
            Text("Drag a pane to move it · drag a bar to resize · drop a tab from an island beside a pane")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Done", action: onDone)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .help("Leave layout mode · Return or Esc")
            // Esc finishes too; a zero-size button carries the shortcut.
            Button("Done", action: onDone)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: LayoutModeBarMetrics.height)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editing split view of \(title)")
    }
}
