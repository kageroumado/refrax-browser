import SwiftUI

// MARK: - Layout mode

extension UnifiedContentView {
    /// The empty cells of the edit: each offers a new page there, and an arrow on each side
    /// where the pane beyond can grow over it.
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

    /// Each pane's controls, the landing of a dragged pane, and the bar that ends the mode.
    func layoutModeControls(grid: PaneGrid, geometry: PaneGridGeometry, frames: [UUID: CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            if let paneDrag, let target = paneDrag.target, let span = grid.moving(paneDrag.pageID, to: target)?.span(of: paneDrag.pageID) {
                let frame = geometry.frame(of: span)
                RoundedRectangle(cornerRadius: geometry.metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.appAccentColor, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: geometry.metrics.cornerRadius, style: .continuous).fill(Color.appAccentColor.opacity(0.1)))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            ForEach(tab.pages) { page in
                if let frame = frames[page.id], paneDrag?.pageID != page.id {
                    PaneEditingPill(
                        page: page,
                        verbs: PaneEditingVerbs(pageID: page.id, grid: grid),
                        onVerb: { perform($0, on: page) },
                    )
                    .frame(width: frame.width)
                    .offset(x: frame.minX, y: frame.minY + PaneEditingPill.Layout.topInset)
                }
            }
            LayoutModeBar { windowState.exitLayoutMode() }
                .frame(width: size.width, height: size.height, alignment: .bottom)
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

    /// A pane moved in layout mode: it follows the pointer, the pane where it would land steps
    /// aside, and letting go trades the two places.
    func paneDragGesture(for pageID: UUID) -> some Gesture {
        DragGesture(minimumDistance: Layout.dragThreshold)
            .onChanged { value in
                guard let session else { return }
                let target = PaneDrop.cell(forDragging: pageID, by: value.translation, in: session.grid, geometry: session.geometry(in: size))
                if paneDrag?.target != target || paneDrag == nil {
                    withAnimation(Layout.dragSpring) {
                        paneDrag = PaneDragState(pageID: pageID, translation: value.translation, target: target)
                    }
                } else {
                    paneDrag?.translation = value.translation
                }
            }
            .onEnded { _ in
                if let target = paneDrag?.target {
                    windowState.editLayout { $0.move(pageID, to: target) }
                }
                withAnimation(Layout.dragSpring) {
                    paneDrag = nil
                }
            }
    }
}

// MARK: - Verbs

/// What a pane can do in layout mode, worked out from the edit's grid.
struct PaneEditingVerbs: Equatable {
    enum Verb: Hashable {
        /// Grow over the empty cells across an edge.
        case grow(PaneEdge)
        /// Give up the half at an edge.
        case shrink(PaneEdge)
        /// Leave the tab as a tab of its own, in the tab's island.
        case openAsTab
        /// Close the page.
        case close
    }

    let grows: [PaneEdge]
    let shrinks: [PaneEdge]
    /// The last pane stays.
    let canLeave: Bool

    init(pageID: UUID, grid: PaneGrid) {
        self.grows = PaneEdge.allCases.filter { grid.expanding(pageID, toward: $0) != nil }
        self.shrinks = PaneEdge.allCases.filter { grid.shrinking(pageID, from: $0) != nil }
        self.canLeave = grid.count > 1
    }

    static func title(of verb: Verb) -> String {
        switch verb {
        case let .grow(edge): "Fill \(name(of: edge))"
        case let .shrink(edge): "Free \(name(of: edge)) Half"
        case .openAsTab: "Open as Its Own Tab"
        case .close: "Close Pane"
        }
    }

    static func symbol(of verb: Verb) -> String {
        switch verb {
        case let .grow(edge): arrow(toward: edge)
        case let .shrink(edge): arrow(toward: edge.opposite)
        case .openAsTab: "rectangle.portrait.and.arrow.right"
        case .close: "xmark"
        }
    }

    private static func name(of edge: PaneEdge) -> String {
        switch edge {
        case .leading: "Left"
        case .trailing: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    static func arrow(toward edge: PaneEdge) -> String {
        switch edge {
        case .leading: "arrow.left"
        case .trailing: "arrow.right"
        case .top: "arrow.up"
        case .bottom: "arrow.down"
        }
    }
}

// MARK: - Views

/// A pane's controls in layout mode: its icon and title in a glass capsule at the top of the
/// pane, the grow and shrink verbs it has, and a menu with the rest.
struct PaneEditingPill: View {
    let page: TabPage
    let verbs: PaneEditingVerbs
    let onVerb: (PaneEditingVerbs.Verb) -> Void

    enum Layout {
        static let topInset: CGFloat = 10
        static let height: CGFloat = 28
        static let faviconSize: CGFloat = 16
        static let titleSize: CGFloat = 13
        static let glyphSize: CGFloat = 12
        static let control: CGFloat = 24
        static let titleWidth: CGFloat = 180
        static let leadingPadding: CGFloat = 10
        static let trailingPadding: CGFloat = 4
    }

    var body: some View {
        HStack(spacing: 6) {
            FaviconView(data: page.faviconData, url: page.url, size: Layout.faviconSize)
            Text(page.title.isEmpty ? page.url.safeDisplayDomain : page.title)
                .font(.system(size: Layout.titleSize))
                .lineLimit(1)
                .frame(maxWidth: Layout.titleWidth, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(verbs.grows, id: \.self) { edge in
                    glyph(.grow(edge))
                }
                Menu {
                    ForEach(verbs.shrinks, id: \.self) { edge in
                        Button(PaneEditingVerbs.title(of: .shrink(edge)), systemImage: PaneEditingVerbs.symbol(of: .shrink(edge))) {
                            onVerb(.shrink(edge))
                        }
                    }
                    if !verbs.shrinks.isEmpty {
                        Divider()
                    }
                    Button(PaneEditingVerbs.title(of: .openAsTab), systemImage: PaneEditingVerbs.symbol(of: .openAsTab)) {
                        onVerb(.openAsTab)
                    }
                    .disabled(!verbs.canLeave)
                    Button(PaneEditingVerbs.title(of: .close), systemImage: PaneEditingVerbs.symbol(of: .close), role: .destructive) {
                        onVerb(.close)
                    }
                    .disabled(!verbs.canLeave)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: Layout.glyphSize))
                        .frame(width: Layout.control, height: Layout.control)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More for this pane")
                .accessibilityLabel("More for \(page.title)")
            }
            .foregroundStyle(.secondary)
        }
        .padding(.leading, Layout.leadingPadding)
        .padding(.trailing, Layout.trailingPadding)
        .frame(height: Layout.height)
        .glassEffect(.regular, in: .capsule)
    }

    private func glyph(_ verb: PaneEditingVerbs.Verb) -> some View {
        Button {
            onVerb(verb)
        } label: {
            Image(systemName: PaneEditingVerbs.symbol(of: verb))
                .font(.system(size: Layout.glyphSize))
                .frame(width: Layout.control, height: Layout.control)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(PaneEditingVerbs.title(of: verb))
        .accessibilityLabel(PaneEditingVerbs.title(of: verb))
    }
}

/// A cell no pane covers in layout mode: a new page opens there from the Command Lens, a row
/// dropped from an island lands there, and the panes beside it can grow over it.
struct EmptyPaneCell: View {
    let cell: GridCell
    let cornerRadius: CGFloat
    /// The pane on each side of the cell that can grow over it.
    let growers: [PaneEdge: UUID]
    let onOpen: () -> Void
    let onGrow: (UUID, PaneEdge) -> Void

    private enum Layout {
        static let symbolSize: CGFloat = 28
        static let arrowInset: CGFloat = 12
        static let control: CGFloat = 28
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            Button(action: onOpen) {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: Layout.symbolSize, weight: .light))
                    Text("Open a page here")
                        .font(.callout)
                    Text("or drop a tab from an island")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: Layout.control, height: Layout.control)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: .circle)
                    .help("Grow the neighboring pane over this cell")
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

/// The bar at the bottom of the page in layout mode: what can be done, and Done.
struct LayoutModeBar: View {
    let onDone: () -> Void

    private enum Layout {
        static let bottomInset: CGFloat = 20
        static let height: CGFloat = 36
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Drag a pane to move it · drag a gap to resize · drop a tab beside a pane to add it")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Done", action: onDone)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.cancelAction)
                .help("Leave layout mode · Esc")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: Layout.height)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, Layout.bottomInset)
    }
}
